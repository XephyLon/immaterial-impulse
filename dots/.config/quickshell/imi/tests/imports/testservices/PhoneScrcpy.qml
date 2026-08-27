pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import qs.modules.common

// Logic-only double of services/PhoneScrcpy.qml: the supervisor Process
// and its timers are replaced by `sentMessages`, which records what
// `send()` would have written; everything between the sync markers is
// byte-for-byte the real service's (tests/test_phone_sessions_contract.py
// enforces it).
Singleton {
    id: root

    property bool available: false
    property bool appModeSupported: false
    readonly property var activeDevice: PhoneConnect.activeDevice
    readonly property string activeDeviceId: String(PhoneConnect.activeDevice?.id ?? "")

    property bool mirrorRunning: false
    property bool mirrorLaunching: false
    property string lastError: ""
    property string mirrorError: ""

    property var apps: []
    property bool appsLoading: false
    property string appsError: ""

    readonly property alias sessions: sessionsModel
    readonly property int sessionCount: sessionsModel.count

    readonly property var favorites: Config.options.phone.scrcpy.appMode.favoritePackages
    readonly property var recents: Persistent.states.phone.scrcpy.recentPackages
    readonly property int maxRecents: 20

    property string managerState: "idle"
    property int restartAttempts: 0
    readonly property int maxRestartAttempts: 5
    property var pendingMessages: []

    signal feedback(string message, bool ok)

    ListModel {
        id: sessionsModel
        dynamicRoles: true
    }

    // BEGIN phone-scrcpy logic (synced with services/PhoneScrcpy.qml)
    // The mirror's flags, from Config.options.phone.scrcpy - the sibling
    // fork's table. `--video-buffer` is scrcpy >= 2's name for the display
    // buffer.
    function mirrorArgs(opts: var): var {
        const o = opts ?? {};
        const args = [];
        if (o.stayAwake) args.push("--stay-awake");
        if (o.turnScreenOff) args.push("--turn-screen-off");
        if (o.noPowerOn) args.push("--no-power-on");
        if (o.noAudio) args.push("--no-audio");
        if (o.showTouches) args.push("--show-touches");
        if (o.fullscreen) args.push("--fullscreen");
        if (o.alwaysOnTop) args.push("--always-on-top");
        if (Number(o.maxFps) > 0) args.push("--max-fps=" + Number(o.maxFps));
        if (typeof o.bitRate === "string" && o.bitRate.trim() !== "") args.push("--video-bit-rate=" + o.bitRate.trim());
        if (Number(o.maxSize) > 0) args.push("--max-size=" + Number(o.maxSize));
        if (Number(o.videoBuffer) > 0) args.push("--video-buffer=" + Number(o.videoBuffer));
        return args;
    }

    // App mode: one app on a virtual display of its own when flexDisplay is
    // on, otherwise started on the phone's screen and mirrored.
    function appModeArgs(packageName: string, appOpts: var): var {
        const o = appOpts ?? {};
        const args = ["--start-app=" + packageName];
        if (o.flexDisplay) {
            const w = Number(o.displayWidth) > 0 ? Number(o.displayWidth) : 1280;
            const h = Number(o.displayHeight) > 0 ? Number(o.displayHeight) : 960;
            const density = Number(o.density) > 0 ? Number(o.density) : 160;
            args.push("--new-display=" + w + "x" + h + "/" + density);
            args.push("--flex-display");
            if (o.keepActive) args.push("--keep-active");
            if (o.systemDecorations === false) args.push("--no-vd-system-decorations");
        }
        return args;
    }

    // The `-s` target for a wireless phone: the address KDE Connect reaches
    // it on (autoWirelessIp) or the configured one, with the configured
    // port. Empty when the user did not ask for wireless or no address is
    // known - the supervisor then lets adb pick, USB first.
    function targetArgs(opts: var, device: var): var {
        const o = opts ?? {};
        if (!o.useWireless) return [];
        let ip = "";
        if (o.autoWirelessIp) {
            const addresses = device?.reachableAddresses ?? [];
            for (let i = 0; i < addresses.length; i++) {
                const address = String(addresses[i] ?? "").trim();
                if (address.length > 0) { ip = address; break; }
            }
        }
        if (!ip) ip = String(o.wirelessIp ?? "").trim();
        if (!ip) return [];
        const port = String(o.wirelessPort ?? "").trim() || "5555";
        return ["-s", ip.indexOf(":") >= 0 ? ip : ip + ":" + port];
    }

    function sessionIdFor(packageName: string): string {
        return "app:" + packageName;
    }

    // MRU: the package moves to the front, the list is capped.
    function pushRecent(list: var, packageName: string, max: int): var {
        const out = [];
        for (let i = 0; i < (list?.length ?? 0); i++) {
            const entry = String(list[i]);
            if (entry !== packageName) out.push(entry);
        }
        out.unshift(packageName);
        return out.slice(0, max);
    }

    function toggleInList(list: var, packageName: string): var {
        const out = [];
        let found = false;
        for (let i = 0; i < (list?.length ?? 0); i++) {
            const entry = String(list[i]);
            if (entry === packageName) { found = true; continue; }
            out.push(entry);
        }
        if (!found) out.push(packageName);
        return out;
    }

    function isFavorite(packageName: string): bool {
        const list = root.favorites ?? [];
        for (let i = 0; i < list.length; i++)
            if (String(list[i]) === packageName) return true;
        return false;
    }

    function sessionIndex(id: string): int {
        for (let i = 0; i < sessionsModel.count; i++)
            if (sessionsModel.get(i).id === id) return i;
        return -1;
    }

    function isAppRunning(packageName: string): bool {
        return root.sessionIndex(root.sessionIdFor(packageName)) >= 0;
    }

    // Delay before the Nth restart of the supervisor: 1s, 2s, 4s, ... 30s.
    function backoffDelay(attempt: int): int {
        return Math.min(30000, 1000 * Math.pow(2, Math.max(1, attempt) - 1));
    }

    // The supervisor is wanted while anything is live or pending - the
    // idle timer stops it otherwise.
    function managerWanted(): bool {
        return sessionsModel.count > 0 || root.mirrorLaunching || root.appsLoading
            || (root.pendingMessages?.length ?? 0) > 0;
    }

    function parseManagerLine(line: string): var {
        const trimmed = (line ?? "").trim();
        if (trimmed.length === 0) return null;
        try {
            const doc = JSON.parse(trimmed);
            return (doc && typeof doc === "object" && typeof doc.event === "string") ? doc : null;
        } catch (e) {
            return null;
        }
    }

    // One supervisor event onto the model.
    //
    // `started` is the supervisor saying it SPAWNED scrcpy, not that a mirror
    // is on screen - it emits the event the instant Popen returns and has no
    // way to know a window appeared. On a phone adb cannot see, scrcpy prints
    // "Could not find any ADB device" and exits about a second later, so
    // reading the spawn as `mirrorRunning` put the card on "scrcpy Mirror /
    // Mirror is running - click to focus its window", a filled check mark and
    // "Active for 0s" where no mirror could possibly exist, and then dropped
    // it back to the line it had before the click. A spawn therefore keeps
    // the mirror LAUNCHING and arms the settle; the settle, or the exit, is
    // what decides which it was.
    function applyEvent(msg: var): void {
        if (!msg) return;
        const id = String(msg.id ?? "");
        if (msg.event === "started") {
            const row = {
                id: id,
                type: String(msg.type ?? (id === "mirror" ? "mirror" : "app")),
                title: String(msg.title ?? ""),
                pid: Number(msg.pid ?? 0),
                package: id.startsWith("app:") ? id.substring(4) : "",
                startedAt: Date.now()
            };
            const index = root.sessionIndex(id);
            if (index >= 0) {
                for (const key in row) if (key !== "startedAt") sessionsModel.setProperty(index, key, row[key]);
            } else {
                sessionsModel.append(row);
            }
            if (id === "mirror") {
                // `alreadyRunning` is the supervisor answering about a child
                // it has been watching since some earlier launch, which IS
                // evidence of a live session - there is nothing to settle.
                if (msg.alreadyRunning === true) {
                    root.cancelMirrorSettle();
                    root.mirrorRunning = true;
                    root.mirrorLaunching = false;
                } else {
                    root.mirrorRunning = false;
                    root.mirrorLaunching = true;
                    root.armMirrorSettle();
                }
            }
        } else if (msg.event === "exited") {
            const index = root.sessionIndex(id);
            if (index >= 0) sessionsModel.remove(index);
            const failure = Number(msg.code ?? 0) !== 0 ? String(msg.error ?? "") : "";
            if (id === "mirror") {
                const wasLaunching = root.mirrorLaunching;
                root.cancelMirrorSettle();
                root.mirrorRunning = false;
                root.mirrorLaunching = false;
                // A mirror that exits before it has settled never opened, so
                // the click produced nothing at all - and the only other line
                // the card has is the precondition the user already read
                // before clicking, which is why a silent snap back to it
                // reads as the card having ignored them.
                root.mirrorError = failure.length > 0 ? failure
                    : (wasLaunching ? "scrcpy exited before the mirror window opened" : "");
            }
            if (failure.length > 0) {
                root.lastError = failure;
                root.feedback(root.lastError, false);
            }
        } else if (msg.event === "error") {
            if (id === "mirror") {
                root.cancelMirrorSettle();
                root.mirrorLaunching = false;
                root.mirrorRunning = false;
                root.mirrorError = String(msg.message ?? "scrcpy error");
            }
            root.lastError = String(msg.message ?? "scrcpy error");
            root.feedback(root.lastError, false);
        } else if (msg.event === "apps_list") {
            root.apps = Array.isArray(msg.apps) ? msg.apps : [];
            // A cached list is served before the live one; loading stays on
            // until the live one lands.
            if (msg.cached !== true) {
                root.appsLoading = false;
                root.appsError = "";
            }
        } else if (msg.event === "apps_error") {
            root.appsLoading = false;
            root.appsError = String(msg.message ?? "Failed to list apps");
        }
    }

    // The settle's own answer: a spawned scrcpy still in the session list
    // after the settle has outlived every way a launch fails, so it is a
    // mirror rather than an attempt. A row that has gone means `exited`
    // already answered and this must not put the card back on `running`.
    function mirrorSettled(): void {
        if (root.sessionIndex("mirror") < 0) return;
        root.mirrorLaunching = false;
        root.mirrorRunning = true;
    }

    function handleLine(line: string): void {
        root.applyEvent(root.parseManagerLine(line));
    }

    function deviceId(): string {
        return root.activeDeviceId || "default";
    }

    function scrcpyTarget(): var {
        return root.targetArgs(Config.options.phone.scrcpy, root.activeDevice);
    }

    function launchMirror(): void {
        if (!root.available) {
            root.lastError = "scrcpy is not installed";
            return;
        }
        if (root.mirrorRunning) {
            root.focusMirror();
            return;
        }
        // A launch already in flight answers itself, through the settle or
        // through the supervisor's exit. Without this, a second click inside
        // the settle window gets `alreadyRunning` back - which is the
        // supervisor saying only that the child it spawned a moment ago has
        // not exited yet, i.e. exactly the weak evidence the settle exists to
        // stop reading as a mirror.
        if (root.mirrorLaunching) return;
        root.mirrorLaunching = true;
        root.lastError = "";
        root.mirrorError = "";
        root.send({
            cmd: "launch", id: "mirror", type: "mirror",
            target_args: root.scrcpyTarget(),
            extra_args: root.mirrorArgs(Config.options.phone.scrcpy)
        });
    }

    function stopMirror(): void {
        root.send({ cmd: "stop", id: "mirror" });
    }

    function focusMirror(): void {
        root.send({ cmd: "focus", id: "mirror" });
    }

    function refreshApps(): void {
        if (!root.appModeSupported) return;
        root.appsLoading = true;
        root.appsError = "";
        root.send({ cmd: "list_apps", target_args: root.scrcpyTarget(), deviceId: root.deviceId() });
    }

    function launchApp(packageName: string): void {
        if (!packageName) return;
        if (!root.appModeSupported) {
            root.lastError = "scrcpy 4.0+ is required for App Mode";
            root.feedback(root.lastError, false);
            return;
        }
        if (root.isAppRunning(packageName)) {
            root.focusApp(packageName);
            return;
        }
        root.send({
            cmd: "launch", id: root.sessionIdFor(packageName), type: "app",
            target_args: root.scrcpyTarget(),
            extra_args: root.appModeArgs(packageName, Config.options.phone.scrcpy.appMode)
        });
        Persistent.states.phone.scrcpy.recentPackages =
            root.pushRecent(Persistent.states.phone.scrcpy.recentPackages, packageName, root.maxRecents);
    }

    function stopApp(packageName: string): void {
        if (!packageName) return;
        root.send({ cmd: "stop", id: root.sessionIdFor(packageName) });
    }

    function focusApp(packageName: string): void {
        if (!packageName) return;
        root.send({ cmd: "focus", id: root.sessionIdFor(packageName) });
    }

    function stopAllApps(): void {
        root.send({ cmd: "stop_all" });
    }

    function toggleFavorite(packageName: string): void {
        if (!packageName) return;
        Config.options.phone.scrcpy.appMode.favoritePackages =
            root.toggleInList(Config.options.phone.scrcpy.appMode.favoritePackages, packageName);
    }
    // END phone-scrcpy logic

    // The settle is a Timer in the real service; here it is a flag the test
    // advances with fireMirrorSettle(), the way every other timer in this
    // module is a counter - the region above calls the two hooks and cannot
    // see which of the two it got.
    property int mirrorSettleArmed: 0
    property bool mirrorSettlePending: false

    function armMirrorSettle(): void {
        root.mirrorSettleArmed++;
        root.mirrorSettlePending = true;
    }

    function cancelMirrorSettle(): void {
        root.mirrorSettlePending = false;
    }

    function fireMirrorSettle(): void {
        if (!root.mirrorSettlePending) return;
        root.mirrorSettlePending = false;
        root.mirrorSettled();
    }

    property var sentMessages: []
    property var feedbackLog: []
    onFeedback: (message, ok) => { root.feedbackLog = root.feedbackLog.concat([{ message: message, ok: ok }]); }

    function send(message: var): void {
        root.sentMessages = root.sentMessages.concat([message]);
    }

    function reset(): void {
        sessionsModel.clear();
        root.mirrorRunning = false;
        root.mirrorLaunching = false;
        root.lastError = "";
        root.mirrorError = "";
        root.mirrorSettleArmed = 0;
        root.mirrorSettlePending = false;
        root.apps = [];
        root.appsLoading = false;
        root.appsError = "";
        root.pendingMessages = [];
        root.sentMessages = [];
        root.feedbackLog = [];
    }
}
