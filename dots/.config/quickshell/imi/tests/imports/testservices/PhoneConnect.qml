pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Logic-only double of services/PhoneConnect.qml. The parser/normalization
// functions between the sync markers are kept byte-for-byte in sync with the
// real service (tests/test_phone_connect_contract.py enforces it); the busctl
// Process/Timer I/O is omitted so tests stay deterministic and offline.
Singleton {
    id: root

    property bool installed: false // busctl found on PATH
    property string backend: "none" // "kdeconnect" | "valent" | "none"
    readonly property bool available: root.backend !== "none"
    // [{ id, name, type, reachable, paired, hasPairingRequest, reachableAddresses,
    //    cellularNetworkType, cellularNetworkStrength,
    //    batteryAvailable, batteryCharge, batteryCharging }]
    property var devices: []
    // The devices whose peer has asked to pair - what the dialog's pairing
    // cards are drawn from.
    readonly property var pairingRequests: root.devices.filter(d => d.hasPairingRequest === true)

    readonly property var activeDevice: root.devices.find(d => d.paired && d.reachable && d.type === "phone")
        ?? root.devices.find(d => d.paired && d.reachable)
        ?? null
    readonly property string materialSymbol: (root.available && root.activeDevice) ? "mobile" : "mobile_off"

    // BEGIN phone-connect parser logic (synced with services/PhoneConnect.qml)
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
    // battery GetAll and its connectivity_report GetAll, either null when
    // that leaf object does not exist - both are absent for unpaired
    // devices) onto the shared device model.
    //
    // A pairing request is Device::PairState 2 (RequestedByPeer; 1 is a
    // request WE made, 3 is Paired) or the older isPairRequestedByPeer bool
    // - both were read off the live daemon, and either spelling counts.
    function normalizeKdeconnectDevice(id: string, rawProps: var, rawBatteryProps: var, rawConnectivityProps: var): var {
        const props = root.unwrapVariants(rawProps);
        const battery = rawBatteryProps === null || rawBatteryProps === undefined
            ? null : root.unwrapVariants(rawBatteryProps);
        const report = rawConnectivityProps === null || rawConnectivityProps === undefined
            ? null : root.unwrapVariants(rawConnectivityProps);
        const addresses = Array.isArray(props.reachableAddresses)
            ? props.reachableAddresses.filter(address => typeof address === "string") : [];
        return {
            id: id,
            name: props.name ?? "",
            type: props.type ?? "",
            reachable: props.isReachable === true,
            paired: props.isPaired === true,
            hasPairingRequest: props.isPairRequestedByPeer === true || props.pairState === 2,
            reachableAddresses: addresses,
            cellularNetworkType: typeof report?.cellularNetworkType === "string" ? report.cellularNetworkType : "",
            cellularNetworkStrength: typeof report?.cellularNetworkStrength === "number" ? report.cellularNetworkStrength : -1,
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
                hasPairingRequest: false,
                reachableAddresses: [],
                cellularNetworkType: "",
                cellularNetworkStrength: -1,
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
            "org.kde.kdeconnect.device.battery": ["refreshed"],
            "org.kde.kdeconnect.device.connectivity_report": ["refreshed"]
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

    // What the share plugin may be handed as a URL: a file:// or http(s)://
    // string, trimmed. Everything else - a bare path, an empty picker line,
    // a non-string - is dropped rather than sent as a URL the daemon
    // cannot open.
    function shareableUrls(entries: var): var {
        if (!Array.isArray(entries)) return [];
        return entries
            .map(entry => typeof entry === "string" ? entry.trim() : "")
            .filter(entry => /^(file|https?):\/\//i.test(entry));
    }

    // What to do with the desktop clipboard: a link goes as a URL, prose as
    // text, nothing is refused. The URL heuristic is the fork's - a scheme,
    // or a host-shaped token that is the whole string or the start of a
    // path. A bare host leaves with https:// on it: the daemon hands the
    // string to a QUrl, and a schemeless one is relative to nothing.
    function clipboardShareTarget(text: var): var {
        const value = (typeof text === "string" ? text : "").trim();
        if (value.length === 0) return { kind: "empty", value: "" };
        if (/^https?:\/\//i.test(value)) return { kind: "url", value: value };
        if (/^[\w.-]+\.\w{2,}(\/|$)/.test(value)) return { kind: "url", value: `https://${value}` };
        return { kind: "text", value: value };
    }
    // END phone-connect parser logic

    function applyBackend(newBackend: string): void {
        root.backend = newBackend;
        if (newBackend === "none") root.devices = [];
    }

    function applyDevices(list: var): void {
        root.devices = root.sortDevices(list);
    }
}
