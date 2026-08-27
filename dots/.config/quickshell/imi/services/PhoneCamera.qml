pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * The phone as a webcam, through DroidCam
 * (docs/superpowers/specs/2026-08-27-phone-tab-design.md, W3).
 *
 * `droidcam-cli` streams the phone's camera into a v4l2loopback device.
 * It is launched DETACHED through scripts/phone/droidcam_session.sh - the
 * pidfile is the binary's own - so the webcam survives a shell restart and
 * is re-adopted at boot from the session's state file. No streaming
 * Process lives here: every command is a one-shot argv through one
 * serialized queue, and liveness is the session script's `status` verb on
 * a watchdog.
 *
 * Connection, USB first: an explicit `connection: "usb"` or a configured
 * Wi-Fi address is taken as written; otherwise `adb get-state` answering
 * `device` wins, then the first address KDE Connect reports for the phone.
 *
 * Everything between the sync markers is kept byte-for-byte in sync with
 * the logic-only double (tests/imports/testservices/PhoneCamera.qml);
 * tests/test_phone_sessions_contract.py enforces it.
 */
Singleton {
    id: root

    readonly property bool available: PhoneDeps.droidcamCli
        && (PhoneDeps.v4l2loopbackLoaded || PhoneDeps.v4l2loopbackInstalled)
    readonly property bool deviceReachable: PhoneConnect.activeDevice?.reachable === true
    readonly property string activeDeviceId: String(PhoneConnect.activeDevice?.id ?? "")

    property bool connecting: false
    property bool active: false
    // unavailable | offline | connecting | ready | active
    readonly property string state: root.stateFor(root.available, root.deviceReachable, root.connecting, root.active)

    property string device: "" // /dev/videoN
    property string activeMode: "" // usb | wifi
    property string activeIp: ""
    property int activePort: 0
    property int sessionPid: 0
    property int startedAt: 0 // unix seconds
    property string lastError: ""
    property bool userStopped: false

    readonly property string sessionScript: `${Directories.scriptPath}/phone/droidcam_session.sh`
    readonly property int connectTimeoutMs: 9000
    readonly property int successAfterMs: 6000

    signal errorOccurred(string message)

    // BEGIN phone-camera logic (synced with tests/imports/testservices/PhoneCamera.qml)
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

    function openPreview(): void {
        const argv = root.previewCommand(root.device, PhoneDeps);
        if (argv.length === 0) {
            root.lastError = "No preview player found - install mpv";
            root.errorOccurred(root.lastError);
            return;
        }
        Quickshell.execDetached(argv);
    }
    // END phone-camera logic

    // ---- timers ----

    property real connectStartedAt: 0

    function connectDeadlinePassed(): bool {
        return Date.now() - root.connectStartedAt >= root.connectTimeoutMs;
    }

    function armConnectTimers(): void {
        root.connectStartedAt = Date.now();
        successTimer.restart();
        failTimer.restart();
    }

    function armWatchdog(): void { watchdog.restart(); }
    function disarmWatchdog(): void {
        watchdog.stop();
        successTimer.stop();
        failTimer.stop();
    }

    // droidcam-cli stays alive through connection negotiation and prints
    // transient errors; a process still alive this long in is a connection.
    Timer {
        id: successTimer
        interval: root.successAfterMs
        onTriggered: if (root.connecting) root.checkSession()
    }

    Timer {
        id: failTimer
        interval: root.connectTimeoutMs
        onTriggered: if (root.connecting) root.checkSession()
    }

    Timer {
        id: watchdog
        interval: 5000
        repeat: true
        onTriggered: {
            if (!root.active) { watchdog.stop(); return; }
            root.checkSession();
        }
    }

    // ---- the serialized command queue ----

    property var callQueue: []
    property var activeCallback: null

    function run(argv: var, callback: var): void {
        root.callQueue.push({ argv: argv, callback: callback });
        root.pump();
    }

    function pump(): void {
        if (cmdProc.running || root.callQueue.length === 0) return;
        const next = root.callQueue.shift();
        root.activeCallback = next.callback;
        cmdProc.exec(next.argv);
    }

    Process {
        id: cmdProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector { id: cmdOut }
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
            const callback = root.activeCallback;
            root.activeCallback = null;
            callback?.(cmdOut.text, exitCode);
            root.pump();
        }
    }

    // A webcam left running by the previous shell is adopted, not doubled.
    Component.onCompleted: root.checkSession()

    onActiveDeviceIdChanged: if (root.active || root.connecting) root.stop()
}
