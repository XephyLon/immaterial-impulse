pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import qs.modules.common

// Logic-only double of services/PhoneCamera.qml: the serialized command
// queue is `run()` answering synchronously from `responder`, recording
// every argv in `ranCommands`; timers are inert. Everything between the
// sync markers is byte-for-byte the real service's
// (tests/test_phone_sessions_contract.py enforces it).
Singleton {
    id: root

    property bool available: false
    property bool deviceReachable: PhoneConnect.activeDevice?.reachable === true
    readonly property string activeDeviceId: String(PhoneConnect.activeDevice?.id ?? "")

    property bool connecting: false
    property bool active: false
    readonly property string state: root.stateFor(root.available, root.deviceReachable, root.connecting, root.active)

    property string device: ""
    property string activeMode: ""
    property string activeIp: ""
    property int activePort: 0
    property int sessionPid: 0
    property int startedAt: 0
    property string lastError: ""
    property bool userStopped: false

    readonly property string sessionScript: "/mock/phone/droidcam_session.sh"
    readonly property int connectTimeoutMs: 9000
    readonly property int successAfterMs: 6000

    signal errorOccurred(string message)

    // BEGIN phone-camera logic (synced with services/PhoneCamera.qml)
    function stateFor(available: bool, reachable: bool, connecting: bool, active: bool): string {
        if (!available) return "unavailable";
        if (active) return "active";
        if (connecting) return "connecting";
        if (!reachable) return "offline";
        return "ready";
    }

    // `v4l2-ctl --list-devices` prints a name line per device followed by
    // its indented nodes. The first node under a DroidCam block wins; a
    // loopback block is the fallback.
    function parseV4l2Devices(text: string): string {
        const lines = (text ?? "").split("\n");
        const firstNodeUnder = (matcher) => {
            let inBlock = false;
            for (const raw of lines) {
                const line = raw.replace(/\s+$/, "");
                if (line.length === 0) continue;
                const isNode = /^\s+\/dev\/video\d+/.test(line);
                if (!isNode) {
                    inBlock = matcher.test(line);
                    continue;
                }
                if (inBlock) return line.trim();
            }
            return "";
        };
        return firstNodeUnder(/droid\s*cam/i) || firstNodeUnder(/loopback|dummy/i);
    }

    // droidcam-cli 2.1.5: single-dash flags, `-size=WxH`, then either
    // `adb <port>` or `<ip> <port>`. Facing is not a flag (the app decides);
    // 180 degrees is both flips.
    function droidcamArgs(conf: var, mode: string, ip: string, port: int): var {
        const c = conf ?? {};
        const args = ["droidcam-cli", "-nocontrols"];
        const size = String(c.resolution ?? "").trim();
        if (size.length > 0) args.push("-size=" + size);
        const rotate180 = Number(c.rotateDegrees) === 180;
        if (c.mirrorHorizontally || rotate180) args.push("-hflip");
        if (rotate180) args.push("-vflip");
        if (mode === "usb") args.push("adb", String(port));
        else args.push(String(ip), String(port));
        return args;
    }

    // Where to connect, USB first. `adbState` is `adb get-state`'s answer
    // (or "" when adb is absent); `addresses` is what KDE Connect reports.
    function connectionPlan(conf: var, adbState: string, addresses: var): var {
        const c = conf ?? {};
        const port = Number(c.port) > 0 ? Number(c.port) : 4747;
        if (c.connection === "usb") return { mode: "usb", ip: "", port: port };
        const configured = String(c.wifiIp ?? "").trim();
        if (configured.length > 0) return { mode: "wifi", ip: configured, port: port };
        if (String(adbState ?? "").trim() === "device") return { mode: "usb", ip: "", port: port };
        for (let i = 0; i < (addresses?.length ?? 0); i++) {
            const address = String(addresses[i] ?? "").trim();
            if (address.length > 0) return { mode: "wifi", ip: address, port: port };
        }
        return { error: "Could not detect USB or Wi-Fi IP. Plug the phone in with USB debugging on, or set the phone's Wi-Fi IP from the DroidCam app in the webcam settings." };
    }

    // The preview player: mpv, else ffplay, else vlc. Empty when none is there.
    function previewCommand(device: string, deps: var): var {
        const d = deps ?? {};
        if (!device) return [];
        if (d.mpv) return ["mpv", "--profile=low-latency", "--no-fullscreen", "--no-osc",
                           "--title=imi webcam preview", "av://v4l2:" + device];
        if (d.ffplay) return ["ffplay", "-fflags", "nobuffer", "-framedrop",
                              "-window_title", "imi webcam preview", "-f", "v4l2", "-i", device];
        if (d.vlc) return ["vlc", "--no-video-title-show", "--no-fullscreen", "v4l2://" + device];
        return [];
    }

    // One `droidcam_session.sh status video` reply.
    function parseSessionStatus(text: string): var {
        try {
            const doc = JSON.parse((text ?? "").trim());
            if (!doc || typeof doc !== "object") return null;
            return {
                alive: doc.alive === true || doc.alive === "true",
                pid: parseInt(doc.pid) || 0,
                started: parseInt(doc.started) || 0,
                port: parseInt(doc.port) || 0,
                mode: String(doc.mode ?? ""),
                ip: String(doc.ip ?? ""),
                device: String(doc.device ?? "")
            };
        } catch (e) {
            return null;
        }
    }

    function fail(message: string): void {
        root.connecting = false;
        root.active = false;
        root.lastError = message;
        root.errorOccurred(message);
    }

    function start(): void {
        if (!root.available || root.connecting || root.active) return;
        if (!root.deviceReachable) {
            root.fail("No reachable phone - pair a device first");
            return;
        }
        root.connecting = true;
        root.userStopped = false;
        root.lastError = "";
        const conf = Config.options.phone.webcam;
        const direct = root.connectionPlan(conf, "", []);
        if (!direct.error) {
            root.launch(direct);
            return;
        }
        root.run(["adb", "get-state"], (text, code) => {
            const plan = root.connectionPlan(conf, code === 0 ? text : "",
                PhoneConnect.activeDevice?.reachableAddresses ?? []);
            if (plan.error) {
                root.fail(plan.error);
                return;
            }
            root.launch(plan);
        });
    }

    function launch(plan: var): void {
        const conf = Config.options.phone.webcam;
        root.activeMode = plan.mode;
        root.activeIp = plan.ip;
        root.activePort = plan.port;
        Persistent.states.phone.camera.lastMode = plan.mode;
        Persistent.states.phone.camera.lastIp = plan.ip;
        Persistent.states.phone.camera.lastPort = plan.port;
        const argv = ["bash", root.sessionScript, "launch", "video"]
            .concat(root.droidcamArgs(conf, plan.mode, plan.ip, plan.port));
        root.run(argv, (text, code) => {
            if (!root.connecting) return;
            if (code !== 0) {
                root.fail("DroidCam did not start - is the DroidCam app open on the phone?");
                return;
            }
            root.sessionPid = parseInt(text) || 0;
            root.armConnectTimers();
        });
    }

    function adoptStatus(status: var): void {
        root.sessionPid = status.pid;
        root.startedAt = status.started;
        root.activeMode = status.mode;
        root.activeIp = status.ip;
        root.activePort = status.port;
        if (status.device) root.device = status.device;
        root.connecting = false;
        root.active = true;
        root.lastError = "";
        if (!status.device) root.detectDevice();
        root.armWatchdog();
    }

    function checkSession(): void {
        root.run(["bash", root.sessionScript, "status", "video"], (text, code) => {
            const status = root.parseSessionStatus(text);
            if (status && status.alive) {
                if (!root.active) root.adoptStatus(status);
                return;
            }
            if (root.active) {
                root.active = false;
                root.device = "";
                root.disarmWatchdog();
                if (!root.userStopped) root.fail("The webcam stream ended");
            } else if (root.connecting && root.connectDeadlinePassed()) {
                root.fail("Could not connect within " + Math.round(root.connectTimeoutMs / 1000)
                    + "s - check that the DroidCam app is open and in Start mode");
            }
        });
    }

    function detectDevice(): void {
        if (!PhoneDeps.v4l2Ctl) return;
        root.run(["v4l2-ctl", "--list-devices"], (text, code) => {
            const found = root.parseV4l2Devices(text);
            if (found) root.device = found;
        });
    }

    function stop(): void {
        if (!root.connecting && !root.active) return;
        root.userStopped = true;
        root.disarmWatchdog();
        root.connecting = false;
        root.active = false;
        root.device = "";
        root.sessionPid = 0;
        root.run(["bash", root.sessionScript, "stop", "video"], null);
    }

    function toggle(): void {
        if (root.connecting || root.active) root.stop();
        else root.start();
    }

    // Facing is the DroidCam app's setting; the shell only records the
    // choice for the card.
    function flip(): void {
        const conf = Config.options.phone.webcam;
        conf.cameraFacing = conf.cameraFacing === "front" ? "back" : "front";
    }

    function mirror(on: bool): void {
        Config.options.phone.webcam.mirrorHorizontally = on;
        if (root.active && root.device && PhoneDeps.v4l2Ctl)
            root.run(["v4l2-ctl", "-d", root.device, "--set-ctrl=horizontal_flip=" + (on ? "1" : "0")], null);
    }

    // The preview belongs to the SESSION, not to the desktop: a player left
    // on a /dev/videoN that has stopped producing frames holds its last frame
    // on screen for ever, which is what it looks like when nothing owns it.
    // So the player is started through startPreview() - a handle, never a
    // detached spawn - and a second click while one is up is not a second
    // window.
    function openPreview(): void {
        if (root.previewRunning) return;
        const argv = root.previewCommand(root.device, PhoneDeps);
        if (argv.length === 0) {
            root.lastError = "No preview player found - install mpv";
            root.errorOccurred(root.lastError);
            return;
        }
        root.startPreview(argv);
    }

    function closePreview(): void {
        if (!root.previewRunning) return;
        root.stopPreview();
    }

    // One observer rather than a closePreview() in stop(), in checkSession()'s
    // death branch and in fail(): `active` IS the session, so every way the
    // session can end arrives here - the stop button, the watchdog finding the
    // pidfile dead, a connect that timed out, and the device disappearing,
    // which reaches it through onActiveDeviceIdChanged's own stop().
    onActiveChanged: if (!root.active) root.closePreview();
    // END phone-camera logic

    // The player, as a record of what the service asked for: `run()`'s shape
    // one process down. The real service hands these to a Process it owns
    // (services/PhoneCamera.qml, the previewProc block); what a double can
    // answer for is the DECISIONS - which argv, whether a second click opens
    // a second window, and which endings close it.
    property bool previewRunning: false
    property var previewCommands: []
    property int previewStops: 0

    function startPreview(argv: var): void {
        root.previewCommands = root.previewCommands.concat([argv]);
        root.previewRunning = true;
    }

    function stopPreview(): void {
        root.previewStops++;
        root.previewRunning = false;
    }

    property real connectStartedAt: 0
    property bool deadlinePassed: false
    function connectDeadlinePassed(): bool { return root.deadlinePassed; }
    property int connectTimersArmed: 0
    property int watchdogArmed: 0
    function armConnectTimers(): void { root.connectTimersArmed++; }
    function armWatchdog(): void { root.watchdogArmed++; }
    function disarmWatchdog(): void { root.watchdogArmed = 0; }

    // responder(argv) -> { text, code } or null (empty output, exit 0)
    property var responder: null
    property var ranCommands: []

    function run(argv: var, callback: var): void {
        root.ranCommands = root.ranCommands.concat([argv]);
        const reply = root.responder ? root.responder(argv) : null;
        callback?.(reply?.text ?? "", reply?.code ?? 0);
    }

    function reset(): void {
        root.connecting = false;
        root.active = false;
        root.device = "";
        root.activeMode = "";
        root.activeIp = "";
        root.activePort = 0;
        root.sessionPid = 0;
        root.startedAt = 0;
        root.lastError = "";
        root.userStopped = false;
        root.deadlinePassed = false;
        root.connectTimersArmed = 0;
        root.watchdogArmed = 0;
        root.responder = null;
        root.ranCommands = [];
        // After `active`, never before: clearing it above runs the same
        // onActiveChanged the service does, which would spend a stop on the
        // counter this line is resetting.
        root.previewRunning = false;
        root.previewCommands = [];
        root.previewStops = 0;
    }
}
