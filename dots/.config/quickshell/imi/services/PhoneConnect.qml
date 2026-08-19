pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * Paired-phone state via KDE Connect or Valent (docs/proposals/phone-connect.md).
 *
 * The shell has no D-Bus binding, so both daemons are driven through
 * `busctl --json=short` Process calls - structured JSON replies, argv arrays,
 * never shell strings. Backend detection reads the bus name list: whichever
 * daemon owns its well-known name wins, KDE Connect first on a tie (running
 * both daemons double-pairs phones anyway). No daemon at all is a clean
 * degraded state: backend "none", no devices, UI hides.
 *
 * Updates are signal-driven where the signal set has been verified against a
 * live daemon, and polled where it has not. KDE Connect gets a
 * `busctl --json=short monitor` subscribed to a match rule; Valent keeps the
 * poll, because no Valent daemon was reachable to check its signals against
 * and a stream that only works for one backend is a regression in the other.
 * The poll stays on either way as the reconcile that notices a daemon
 * disappearing - slower while the monitor is live.
 *
 * The monitor is a streaming Process, so it is started imperatively and
 * never by a `running` binding: busctl exits in milliseconds on a rule the
 * bus rejects, and a binding would answer that with a tight respawn loop
 * (CONTRIBUTING.md). Restarts go through monitorExitPlan - capped exponential
 * backoff, a per-daemon-appearance retry ceiling, and a healthy-run reset -
 * after which polling is the whole update path again.
 *
 * Device ids and object paths get spliced into D-Bus object paths, so both
 * are validated first (validDeviceId / validValentObjectPath); anything that
 * fails the check is dropped rather than escaped.
 *
 * The parser/normalization functions between the sync markers are kept
 * byte-for-byte in sync with the logic-only test double
 * (tests/imports/testservices/PhoneConnect.qml);
 * tests/test_phone_connect_contract.py enforces it.
 */
Singleton {
    id: root

    readonly property int pollInterval: Config.options.networking?.phoneConnect?.pollInterval ?? 10000
    readonly property bool enableService: Config.options.networking?.phoneConnect?.enable ?? true

    property bool installed: false // busctl found on PATH
    property string backend: "none" // "kdeconnect" | "valent" | "none"
    readonly property bool available: root.backend !== "none"
    // [{ id, name, type, reachable, paired, batteryAvailable, batteryCharge, batteryCharging }]
    property var devices: []

    readonly property var activeDevice: root.devices.find(d => d.paired && d.reachable && d.type === "phone")
        ?? root.devices.find(d => d.paired && d.reachable)
        ?? null
    readonly property string materialSymbol: (root.available && root.activeDevice) ? "mobile" : "mobile_off"

    // Valent action names beyond findmyphone.ring were not verifiable against
    // a live daemon, so only the verified surface is offered there.
    readonly property bool canPing: root.backend === "kdeconnect"
    readonly property bool canSendClipboard: root.backend === "kdeconnect"

    // BEGIN phone-connect parser logic (synced with tests/imports/testservices/PhoneConnect.qml)
    // Parses one `busctl --json=short` reply. Returns the payload ("data")
    // array, or null when the text is not a busctl JSON document (empty
    // output, "Call failed: ..." error text, malformed JSON).
    function parseBusctlReply(text: string): var {
        const trimmed = (text ?? "").trim();
        if (trimmed.length === 0) return null;
        let doc;
        try {
            doc = JSON.parse(trimmed);
        } catch (e) {
            return null;
        }
        if (!doc || typeof doc !== "object" || !Array.isArray(doc.data)) return null;
        return doc.data;
    }

    // GetAll replies carry a{sv}: { key: { type, data } }. Flattens the
    // variant cells to plain values.
    function unwrapVariants(dict: var): var {
        const out = {};
        for (const key in (dict ?? {})) {
            const cell = dict[key];
            out[key] = (cell && typeof cell === "object" && "data" in cell) ? cell.data : cell;
        }
        return out;
    }

    // Maps a ListNames reply to the backend it implies. KDE Connect wins a
    // tie: it is the incumbent, and running both daemons at once double-pairs
    // phones anyway.
    function backendFromNames(names: var): string {
        const list = names ?? [];
        if (list.includes("org.kde.kdeconnect.daemon")) return "kdeconnect";
        if (list.includes("ca.andyholmes.Valent")) return "valent";
        return "none";
    }

    // Normalizes one org.kde.kdeconnect.device GetAll reply (plus its
    // battery GetAll, or null when the battery object does not exist - it is
    // absent for unpaired devices) onto the shared device model.
    function normalizeKdeconnectDevice(id: string, rawProps: var, rawBatteryProps: var): var {
        const props = root.unwrapVariants(rawProps);
        const battery = rawBatteryProps === null || rawBatteryProps === undefined
            ? null : root.unwrapVariants(rawBatteryProps);
        return {
            id: id,
            name: props.name ?? "",
            type: props.type ?? "",
            reachable: props.isReachable === true,
            paired: props.isPaired === true,
            batteryAvailable: battery !== null && typeof battery.charge === "number",
            batteryCharge: (battery !== null && typeof battery.charge === "number") ? battery.charge : -1,
            batteryCharging: battery !== null && battery.isCharging === true
        };
    }

    // Valent device State flags (valent-device.h): 1 = connected, 2 = paired.
    function normalizeValentObjects(managedObjects: var): var {
        const objects = (managedObjects ?? [])[0] ?? {};
        const devices = [];
        for (const path in objects) {
            const ifaces = objects[path];
            const raw = ifaces?.["ca.andyholmes.Valent.Device"];
            if (!raw) continue;
            const props = root.unwrapVariants(raw);
            const state = Number(props.State ?? 0);
            devices.push({
                id: props.Id ?? "",
                name: props.Name ?? "",
                type: props.Type ?? "",
                reachable: (state & 1) !== 0,
                paired: (state & 2) !== 0,
                objectPath: path,
                batteryAvailable: false,
                batteryCharge: -1,
                batteryCharging: false
            });
        }
        return devices;
    }

    // Decodes an org.gtk.Actions DescribeAll reply (a{s(bgav)}) into battery
    // state via the stateful `battery.state` action's vardict.
    function decodeValentBattery(describeAllData: var): var {
        const none = { available: false, charge: -1, charging: false };
        const actions = (describeAllData ?? [])[0] ?? {};
        const batteryAction = actions["battery.state"];
        if (!Array.isArray(batteryAction) || batteryAction.length < 3) return none;
        const stateCells = batteryAction[2];
        if (!Array.isArray(stateCells) || stateCells.length === 0) return none;
        const state = root.unwrapVariants(stateCells[0]?.data ?? null);
        if (typeof state.percentage !== "number") return none;
        return {
            available: state["is-present"] !== false,
            charge: Math.round(state.percentage),
            charging: state.charging === true
        };
    }

    // Reachable-and-paired devices first, then paired, then by name/id.
    function sortDevices(list: var): var {
        const rank = d => (d.paired && d.reachable) ? 0 : d.paired ? 1 : 2;
        return [...(list ?? [])].sort((a, b) => rank(a) - rank(b)
            || String(a.name || a.id).localeCompare(String(b.name || b.id)));
    }

    // Object paths and argv both splice the id in; keep it boring.
    function validDeviceId(id: var): bool {
        return typeof id === "string" && /^[A-Za-z0-9_-]+$/.test(id);
    }

    // The monitor's subscription, as one D-Bus match rule. Narrowing it at
    // the BUS is the only filter there is: `busctl monitor` reports a signal's
    // sender as the unique name it arrived on (":1.55", captured live), so
    // nothing downstream can tell the daemon's signals from anyone else's
    // emitted on the same path. An empty rule means "this backend has no
    // verified signal set" and leaves it on the poll - Valent's case.
    function monitorMatchRule(backend: string): string {
        if (backend === "kdeconnect")
            return "type='signal',sender='org.kde.kdeconnect.daemon',path_namespace='/modules/kdeconnect'";
        return "";
    }

    // One `busctl --json=short monitor` line as { path, iface, member, args },
    // or null. A monitor sees method calls, returns and errors on the same
    // stream; only a signal carries a change.
    function parseMonitorLine(line: string): var {
        const trimmed = (line ?? "").trim();
        if (trimmed.length === 0) return null;
        let doc;
        try {
            doc = JSON.parse(trimmed);
        } catch (e) {
            return null;
        }
        if (!doc || typeof doc !== "object" || doc.type !== "signal") return null;
        return {
            path: doc.path ?? "",
            iface: doc.interface ?? "",
            member: doc.member ?? "",
            args: doc.payload?.data ?? []
        };
    }

    // Which of the daemon's signals can move the device model. An allowlist
    // rather than "anything under org.kde.kdeconnect": the SMS plugin's
    // conversation signals share the device path, and re-reading every device
    // per incoming message is a chain of busctl spawns for a change this
    // service does not model. Members verified by introspecting a live
    // daemon's /modules/kdeconnect and device paths.
    function signalChangesDevices(signal: var): bool {
        if (!signal) return false;
        // PropertiesChanged names the interface it is about in its first arg.
        if (signal.iface === "org.freedesktop.DBus.Properties")
            return signal.member === "PropertiesChanged"
                && String((signal.args ?? [])[0] ?? "").startsWith("org.kde.kdeconnect");
        const members = {
            "org.kde.kdeconnect.daemon": ["deviceAdded", "deviceRemoved", "deviceListChanged",
                "deviceVisibilityChanged", "pairingRequestsChanged"],
            "org.kde.kdeconnect.device": ["reachableChanged", "pairStateChanged", "nameChanged",
                "typeChanged", "pluginsChanged"],
            "org.kde.kdeconnect.device.battery": ["refreshed"]
        }[signal.iface];
        return Array.isArray(members) && members.includes(signal.member);
    }

    // Delay before the Nth consecutive fast monitor exit is retried: 1s, 2s,
    // 4s, 8s, 16s, capped at 30s.
    function monitorBackoffDelay(attempt: int): int {
        return Math.min(30000, 1000 * Math.pow(2, Math.max(1, attempt) - 1));
    }

    // What a monitor exit means, as one decision: the attempt count it leaves
    // behind, whether to restart, and after how long. A run that lasted at
    // least `healthyMs` was working, so it clears the count rather than
    // counting as the next rung of a respawn loop - without that, one daemon
    // restart in a day-long session spends the ceiling and the shell never
    // streams again.
    function monitorExitPlan(attempts: int, ranForMs: int, wanted: bool, healthyMs: int, ceiling: int): var {
        const settled = ranForMs >= healthyMs ? 0 : attempts;
        if (!wanted || settled >= ceiling)
            return { attempts: settled, retry: false, delay: 0 };
        return { attempts: settled + 1, retry: true, delay: root.monitorBackoffDelay(settled + 1) };
    }
    // END phone-connect parser logic

    function applyBackend(newBackend: string): void {
        root.backend = newBackend;
        if (newBackend === "none") root.devices = [];
    }

    function applyDevices(list: var): void {
        root.devices = root.sortDevices(list);
    }

    // Valent exports devices under /ca/andyholmes/Valent/Device/<n>; anything
    // else coming back from ObjectManager is not a path worth calling into.
    function validValentObjectPath(path: var): bool {
        return typeof path === "string" && /^\/ca\/andyholmes\/Valent\/Device\/[A-Za-z0-9_]+$/.test(path);
    }

    function busctlCall(dest: string, path: string, iface: string, member: string, extra: var): var {
        return ["busctl", "--user", "--json=short", "--timeout=5", "call", dest, path, iface, member, ...extra];
    }

    // The match rule is one argv element. It carries quotes the D-Bus match
    // grammar requires, which is exactly why it never goes near a shell.
    function busctlMonitor(matchRule: string): var {
        return ["busctl", "--user", "--json=short", "monitor", `--match=${matchRule}`];
    }

    function refresh(): void {
        if (!root.enableService || !root.installed) return;
        if (busProc.running || root.callQueue.length > 0) return; // previous sweep still in flight
        root.enqueue(root.busctlCall("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames", []), text => {
            const data = root.parseBusctlReply(text);
            const newBackend = data === null ? "none" : root.backendFromNames(data[0] ?? []);
            root.applyBackend(newBackend);
            if (newBackend === "kdeconnect") root.refreshKdeconnect();
            else if (newBackend === "valent") root.refreshValent();
        });
    }

    function refreshKdeconnect(): void {
        root.enqueue(root.busctlCall("org.kde.kdeconnect.daemon", "/modules/kdeconnect", "org.kde.kdeconnect.daemon", "devices", ["bb", "false", "false"]), text => {
            const data = root.parseBusctlReply(text);
            if (data === null) { root.applyDevices([]); return; }
            const ids = (data[0] ?? []).filter(id => root.validDeviceId(id));
            if (ids.length === 0) { root.applyDevices([]); return; }
            const collected = [];
            for (const id of ids) root.collectKdeconnectDevice(id, collected, ids.length);
        });
    }

    function collectKdeconnectDevice(id: string, collected: var, total: int): void {
        const devicePath = `/modules/kdeconnect/devices/${id}`;
        root.enqueue(root.busctlCall("org.kde.kdeconnect.daemon", devicePath, "org.freedesktop.DBus.Properties", "GetAll", ["s", "org.kde.kdeconnect.device"]), propsText => {
            const propsData = root.parseBusctlReply(propsText);
            // The battery object does not exist for unpaired devices; the
            // failed GetAll parses to null and normalization degrades cleanly.
            root.enqueue(root.busctlCall("org.kde.kdeconnect.daemon", devicePath + "/battery", "org.freedesktop.DBus.Properties", "GetAll", ["s", "org.kde.kdeconnect.device.battery"]), batteryText => {
                const batteryData = root.parseBusctlReply(batteryText);
                collected.push(root.normalizeKdeconnectDevice(id, propsData?.[0] ?? {}, batteryData?.[0] ?? null));
                if (collected.length === total) root.applyDevices(collected);
            });
        });
    }

    function refreshValent(): void {
        root.enqueue(root.busctlCall("ca.andyholmes.Valent", "/ca/andyholmes/Valent", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", []), text => {
            const data = root.parseBusctlReply(text);
            if (data === null) { root.applyDevices([]); return; }
            const found = root.normalizeValentObjects(data).filter(d => root.validValentObjectPath(d.objectPath));
            if (found.length === 0) { root.applyDevices([]); return; }
            let pending = found.length;
            for (const device of found) {
                root.enqueue(root.busctlCall("ca.andyholmes.Valent", device.objectPath, "org.gtk.Actions", "DescribeAll", []), describeText => {
                    const battery = root.decodeValentBattery(root.parseBusctlReply(describeText));
                    device.batteryAvailable = battery.available;
                    device.batteryCharge = battery.charge;
                    device.batteryCharging = battery.charging;
                    if (--pending === 0) root.applyDevices(found);
                });
            }
        });
    }

    // ---- signal streaming ----

    property string monitorState: "idle" // idle | running | backoff | failed
    property int monitorAttempts: 0
    property real monitorStartedAt: 0

    readonly property int monitorAttemptCeiling: 5
    // A monitor that held the bus this long was doing its job; anything
    // shorter counts toward the ceiling (see monitorExitPlan).
    readonly property int monitorHealthyMs: 30000

    readonly property bool monitorLive: root.monitorState === "running"

    // A function rather than a binding, and that is not a style choice:
    // onBackendChanged is the caller, and nothing orders a change handler
    // against the re-evaluation of a binding derived from the same property,
    // so a binding here answers with the PREVIOUS backend. Written as one it
    // read false on the transition that arms the stream and the monitor
    // never started - measured against the runtime harness, silently, with
    // the model still updating from the poll.
    function monitorWanted(): bool {
        return root.enableService && root.installed
            && root.monitorState !== "failed" && root.monitorMatchRule(root.backend) !== "";
    }

    function startMonitor(): void {
        if (monitorProc.running || !root.monitorWanted()) return;
        monitorRestart.stop();
        root.monitorStartedAt = Date.now();
        root.monitorState = "running";
        monitorProc.exec(root.busctlMonitor(root.monitorMatchRule(root.backend)));
    }

    function stopMonitor(): void {
        monitorRestart.stop();
        root.monitorAttempts = 0;
        root.monitorState = "idle";
        monitorProc.running = false;
    }

    function handleMonitorLine(line: string): void {
        if (!root.signalChangesDevices(root.parseMonitorLine(line))) return;
        // Signals arrive in bursts - one device going out of range emitted
        // seven within a millisecond of each other on a live daemon - and
        // every re-read is a chain of busctl spawns, so they coalesce.
        signalSettle.restart();
    }

    Timer {
        id: signalSettle
        interval: 120
        onTriggered: {
            // refresh() declines while a sweep is in flight; re-arm rather
            // than drop the change that asked for it.
            if (busProc.running || root.callQueue.length > 0) {
                signalSettle.restart();
                return;
            }
            root.refresh();
        }
    }

    Timer {
        id: monitorRestart
        onTriggered: root.startMonitor()
    }

    Process {
        id: monitorProc
        // process-lifecycle: restart-safe -- capped exponential backoff; no running binding.
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: SplitParser {
            onRead: data => root.handleMonitorLine(data)
        }
        // busctl says nothing here on a rule the bus accepts, and exits
        // non-zero with one line on a rule it does not; either way the exit
        // is what the plan reads.
        stderr: SplitParser {}
        onExited: (exitCode, exitStatus) => {
            const plan = root.monitorExitPlan(root.monitorAttempts, Date.now() - root.monitorStartedAt,
                root.monitorWanted(), root.monitorHealthyMs, root.monitorAttemptCeiling);
            root.monitorAttempts = plan.attempts;
            if (!plan.retry) {
                if (root.monitorWanted()) {
                    root.monitorState = "failed";
                    console.warn(`[PhoneConnect] busctl monitor gave up after ${root.monitorAttemptCeiling} restarts; falling back to polling`);
                } else {
                    root.monitorState = "idle";
                }
                return;
            }
            root.monitorState = "backoff";
            monitorRestart.interval = plan.delay;
            monitorRestart.restart();
        }
    }

    onBackendChanged: {
        // The ceiling is per daemon appearance, not per session: a daemon
        // that has just come back is a new opportunity rather than the sixth
        // rung of the loop that gave up on the old one. Nothing can reach
        // this faster than a ListNames sweep, so it cannot itself become one.
        root.monitorAttempts = 0;
        if (root.monitorState === "failed") root.monitorState = "idle";
        if (root.monitorMatchRule(root.backend) === "") root.stopMonitor();
        else root.startMonitor();
    }

    // ---- actions ----

    function ring(device: var): void {
        const d = device ?? root.activeDevice;
        if (!d) return;
        if (root.backend === "kdeconnect" && root.validDeviceId(d.id))
            root.runAction(root.busctlCall("org.kde.kdeconnect.daemon", `/modules/kdeconnect/devices/${d.id}/findmyphone`, "org.kde.kdeconnect.device.findmyphone", "ring", []));
        else if (root.backend === "valent" && root.validValentObjectPath(d.objectPath))
            root.runAction(root.busctlCall("ca.andyholmes.Valent", d.objectPath, "org.gtk.Actions", "Activate", ["sava{sv}", "findmyphone.ring", "0", "0"]));
    }

    function ping(device: var): void {
        const d = device ?? root.activeDevice;
        if (!d || root.backend !== "kdeconnect" || !root.validDeviceId(d.id)) return;
        root.runAction(root.busctlCall("org.kde.kdeconnect.daemon", `/modules/kdeconnect/devices/${d.id}/ping`, "org.kde.kdeconnect.device.ping", "sendPing", []));
    }

    function sendClipboard(device: var): void {
        const d = device ?? root.activeDevice;
        if (!d || root.backend !== "kdeconnect" || !root.validDeviceId(d.id)) return;
        root.runAction(root.busctlCall("org.kde.kdeconnect.daemon", `/modules/kdeconnect/devices/${d.id}/clipboard`, "org.kde.kdeconnect.device.clipboard", "sendClipboard", []));
    }

    function runAction(argv: var): void {
        actionProc.exec(argv);
    }

    Process {
        id: actionProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stderr: StdioCollector {
            id: actionErr
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Phone Connect"),
                    actionErr.text.trim() || Translation.tr("Phone Connect command failed"),
                    "-a", "Shell"
                ]);
            }
        }
    }

    // ---- serialized busctl queue ----

    property var callQueue: []
    property var activeCallback: null

    function enqueue(argv: var, callback: var): void {
        root.callQueue.push({ argv: argv, callback: callback });
        root.pump();
    }

    function pump(): void {
        if (busProc.running || root.callQueue.length === 0) return;
        const next = root.callQueue.shift();
        root.activeCallback = next.callback;
        busProc.exec(next.argv);
    }

    Process {
        id: busProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            id: busOut
        }
        // "Call failed: ..." on stderr is expected for absent objects (e.g.
        // the battery of an unpaired device); the empty stdout parses to null.
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
            const callback = root.activeCallback;
            root.activeCallback = null;
            callback?.(busOut.text);
            root.pump();
        }
    }

    onEnableServiceChanged: {
        if (!root.enableService) {
            root.callQueue = [];
            root.activeCallback = null;
            root.stopMonitor();
            root.applyBackend("none");
        } else if (root.installed) {
            root.refresh();
        }
    }

    // One-shot presence check; everything else is gated on it.
    Process {
        id: whichProc
        running: root.enableService
        command: ["sh", "-c", "command -v busctl"]
        onExited: (exitCode, exitStatus) => {
            root.installed = (exitCode === 0);
            if (root.installed) root.refresh();
        }
    }

    // While the monitor is live this is no longer the update path - every
    // change already arrives as a signal - but it stays on, slower, as the
    // reconcile that notices a daemon which went away without saying so, and
    // as the detector that notices one arriving in the first place.
    readonly property int reconcileInterval: Math.max(root.pollInterval * 6, 60000)

    Timer {
        interval: root.monitorLive ? root.reconcileInterval : root.pollInterval
        running: root.enableService && root.installed
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
