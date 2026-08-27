pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * The phone as a microphone
 * (docs/superpowers/specs/2026-08-27-phone-tab-design.md, W3).
 *
 * The stream lands on a null sink named DroidCam-Mic, whose `.monitor`
 * source is what applications record from - the routing the sibling fork
 * arrived at, kept exactly:
 *
 *   scrcpy backend (preferred, no app on the phone): scrcpy --no-video
 *   --no-window --audio-source=mic plays through SDL, which opens its
 *   stream on the DEFAULT sink and ignores PULSE_SINK on PipeWire. So the
 *   default sink is swapped to DroidCam-Mic for exactly as long as the
 *   stream takes to appear (`pactl list sink-inputs` polled every 250 ms,
 *   3 s ceiling) and then put back. The original sink is persisted in
 *   Persistent.states.phone.mic.originalDefaultSink so a shell restart
 *   mid-swap still restores it - the boot reconciliation below does that.
 *
 *   droidcam backend: `env PULSE_SINK=DroidCam-Mic droidcam-cli -a`, which
 *   does honour the variable.
 *
 * scripts/phone/setup_droidcam_input.sh loads the null sink (idempotent)
 * and prints the monitor source; teardown_droidcam_input.sh unloads it.
 * Both audio processes are launched DETACHED through droidcam_session.sh
 * so they survive a shell restart and are re-adopted at boot. No streaming
 * Process lives here: every command is a one-shot argv through one
 * serialized queue.
 *
 * Everything between the sync markers is kept byte-for-byte in sync with
 * the logic-only double (tests/imports/testservices/PhoneMic.qml);
 * tests/test_phone_sessions_contract.py enforces it.
 */
Singleton {
    id: root

    readonly property bool available: PhoneDeps.pactl && (PhoneDeps.scrcpy || PhoneDeps.droidcamCli)
    readonly property string preferredBackend: PhoneDeps.scrcpy ? "scrcpy" : (PhoneDeps.droidcamCli ? "droidcam" : "")
    readonly property bool deviceReachable: PhoneConnect.activeDevice?.reachable === true
    readonly property string activeDeviceId: String(PhoneConnect.activeDevice?.id ?? "")

    property bool connecting: false
    property bool active: false
    // unavailable | offline | connecting | ready | active
    readonly property string state: root.stateFor(root.available, root.deviceReachable, root.connecting, root.active)

    property string backend: "" // scrcpy | droidcam, while a session is up
    property bool muted: false
    property int gain: 100
    property bool isDefaultInput: false
    property string previousDefaultSource: ""
    property string pulseSource: "" // the null sink's monitor source
    property string activeMode: "" // usb | wifi | scrcpy
    property string activeIp: ""
    property int activePort: 0
    property int sessionPid: 0
    property int startedAt: 0
    property string lastError: ""
    property bool userStopped: false
    // The user's default sink while it is swapped to DroidCam-Mic; "" when
    // it is not. Mirrors Persistent so a restart can undo the swap.
    property string swappedSink: Persistent.states.phone.mic.originalDefaultSink

    readonly property string sinkName: "DroidCam-Mic"
    readonly property string sessionScript: `${Directories.scriptPath}/phone/droidcam_session.sh`
    readonly property string statusScript: `${Directories.scriptPath}/phone/droidcam_status.sh`
    readonly property string setupScript: `${Directories.scriptPath}/phone/setup_droidcam_input.sh`
    readonly property string teardownScript: `${Directories.scriptPath}/phone/teardown_droidcam_input.sh`
    readonly property int connectTimeoutMs: 10000
    readonly property int verifyAfterMs: 5000
    readonly property int swapPollMs: 250
    readonly property int swapCeilingMs: 3000

    signal errorOccurred(string message)

    // BEGIN phone-mic logic (synced with tests/imports/testservices/PhoneMic.qml)
    function stateFor(available: bool, reachable: bool, connecting: bool, active: bool): string {
        if (!available) return "unavailable";
        if (active) return "active";
        if (connecting) return "connecting";
        if (!reachable) return "offline";
        return "ready";
    }

    function sessionFor(backend: string): string {
        return backend === "scrcpy" ? "scrcpy-mic" : "audio";
    }

    // scrcpy's mic capture, audio only, no window. Routing is the default
    // sink swap, not a flag - there is none.
    function scrcpyMicArgs(targetArgs: var): var {
        return ["scrcpy", "--no-video", "--no-window", "--audio-source=mic", "--audio-buffer=50"]
            .concat(targetArgs ?? []);
    }

    function droidcamAudioArgs(mode: string, ip: string, port: int): var {
        const args = ["env", "PULSE_SINK=" + root.sinkName, "droidcam-cli", "-a", "-nocontrols"];
        if (mode === "usb") args.push("adb", String(port));
        else args.push(String(ip), String(port));
        return args;
    }

    // Same rule as the webcam's: usb when asked, a configured address when
    // given, else adb's answer, else KDE Connect's address.
    function connectionPlan(conf: var, adbState: string, addresses: var): var {
        const c = conf ?? {};
        const port = Number(c.port) > 0 ? Number(c.port) : 4748;
        if (c.connection === "usb") return { mode: "usb", ip: "", port: port };
        const configured = String(c.wifiIp ?? "").trim();
        if (configured.length > 0) return { mode: "wifi", ip: configured, port: port };
        if (String(adbState ?? "").trim() === "device") return { mode: "usb", ip: "", port: port };
        for (let i = 0; i < (addresses?.length ?? 0); i++) {
            const address = String(addresses[i] ?? "").trim();
            if (address.length > 0) return { mode: "wifi", ip: address, port: port };
        }
        return { error: "Could not detect USB or Wi-Fi IP. Plug the phone in with USB debugging on, or set the phone's Wi-Fi IP from the DroidCam app in the microphone settings." };
    }

    // `pactl list sink-inputs` names the application in several properties;
    // any mention of scrcpy is its stream.
    function streamPresent(sinkInputsText: string): bool {
        return /scrcpy/i.test(sinkInputsText ?? "");
    }

    // One droidcam_status.sh reply, the two audio facts.
    function parseStatus(text: string): var {
        try {
            const doc = JSON.parse((text ?? "").trim());
            if (!doc || typeof doc !== "object") return null;
            return {
                audioRunning: doc.audio_running === true,
                audioHasSinkInput: doc.audio_has_sink_input === true,
                audioSource: String(doc.audio_source ?? "")
            };
        } catch (e) {
            return null;
        }
    }

    function parseSessionStatus(text: string): var {
        try {
            const doc = JSON.parse((text ?? "").trim());
            if (!doc || typeof doc !== "object") return null;
            return {
                session: String(doc.session ?? ""),
                alive: doc.alive === true || doc.alive === "true",
                pid: parseInt(doc.pid) || 0,
                started: parseInt(doc.started) || 0,
                port: parseInt(doc.port) || 0,
                mode: String(doc.mode ?? ""),
                ip: String(doc.ip ?? "")
            };
        } catch (e) {
            return null;
        }
    }

    // What to do about the default sink at boot: a default of DroidCam-Mic
    // with no live mic session is a swap the previous shell never undid.
    function restorePlan(defaultSink: string, savedSink: string, sessionAlive: bool): string {
        if (String(defaultSink ?? "").trim() !== root.sinkName) return "";
        if (sessionAlive) return "";
        const saved = String(savedSink ?? "").trim();
        return (saved.length > 0 && saved !== root.sinkName) ? saved : "@DEFAULT_SINK@";
    }

    function muteArgs(source: string, muted: bool): var {
        return ["pactl", "set-source-mute", source, muted ? "1" : "0"];
    }

    function gainArgs(source: string, percent: int): var {
        return ["pactl", "set-source-volume", source, String(Math.max(0, Math.min(200, percent))) + "%"];
    }

    // A launch that went wrong: report it and undo whatever it had done.
    function fail(message: string): void {
        root.connecting = false;
        root.active = false;
        root.lastError = message;
        root.errorOccurred(message);
        root.restoreDefaultSink();
        root.cleanupSession();
    }

    // A launch that never began: nothing to undo.
    function refuse(message: string): void {
        root.lastError = message;
        root.errorOccurred(message);
    }

    function start(): void {
        if (!root.available || root.connecting || root.active) return;
        if (!root.deviceReachable) {
            root.refuse("No reachable phone - pair a device first");
            return;
        }
        root.connecting = true;
        root.userStopped = false;
        root.lastError = "";
        root.backend = root.preferredBackend;
        Persistent.states.phone.mic.lastBackend = root.backend;
        // A loopback left by a previous "hear yourself" would otherwise
        // stay for the whole session.
        root.run(["pactl", "unload-module", "module-loopback"], null);
        root.run(["bash", root.setupScript], (text, code) => {
            if (!root.connecting) return;
            const source = (text ?? "").trim().split("\n")[0] ?? "";
            if (code !== 0 || source.length === 0) {
                root.fail("Failed to create the DroidCam-Mic null sink - pactl may not have permission");
                return;
            }
            root.pulseSource = source;
            if (root.backend === "scrcpy") root.startScrcpy();
            else root.startDroidcam();
        });
        root.armConnectTimers();
    }

    function startScrcpy(): void {
        root.run(["pactl", "get-default-sink"], (text, code) => {
            if (!root.connecting) return;
            const original = (text ?? "").trim();
            if (code !== 0 || original.length === 0) {
                root.fail("Could not read the current default audio sink - audio routing aborted");
                return;
            }
            if (original !== root.sinkName) root.rememberSwap(original);
            root.run(["pactl", "set-default-sink", root.sinkName], (t, c) => {
                if (!root.connecting) return;
                root.activeMode = "scrcpy";
                root.activeIp = "";
                root.activePort = 0;
                const target = PhoneScrcpy.targetArgs(Config.options.phone.scrcpy, PhoneConnect.activeDevice);
                root.run(["bash", root.sessionScript, "launch", "scrcpy-mic"].concat(root.scrcpyMicArgs(target)),
                    (out, rc) => {
                        if (!root.connecting) return;
                        root.sessionPid = parseInt(out) || 0;
                        root.armSwapRestore();
                        root.armVerify();
                    });
            });
        });
    }

    function startDroidcam(): void {
        const conf = Config.options.phone.microphone;
        const direct = root.connectionPlan(conf, "", []);
        if (!direct.error) {
            root.launchDroidcam(direct);
            return;
        }
        root.run(["adb", "get-state"], (text, code) => {
            if (!root.connecting) return;
            const plan = root.connectionPlan(conf, code === 0 ? text : "",
                PhoneConnect.activeDevice?.reachableAddresses ?? []);
            if (plan.error) {
                root.fail(plan.error);
                return;
            }
            root.launchDroidcam(plan);
        });
    }

    function launchDroidcam(plan: var): void {
        root.activeMode = plan.mode;
        root.activeIp = plan.ip;
        root.activePort = plan.port;
        Persistent.states.phone.mic.lastMode = plan.mode;
        Persistent.states.phone.mic.lastIp = plan.ip;
        Persistent.states.phone.mic.lastPort = plan.port;
        root.run(["bash", root.sessionScript, "launch", "audio"]
            .concat(root.droidcamAudioArgs(plan.mode, plan.ip, plan.port)), (out, rc) => {
                if (!root.connecting) return;
                if (rc !== 0) {
                    root.fail("DroidCam did not start - is the DroidCam app open on the phone?");
                    return;
                }
                root.sessionPid = parseInt(out) || 0;
                root.armVerify();
            });
    }

    function rememberSwap(original: string): void {
        root.swappedSink = original;
        Persistent.states.phone.mic.originalDefaultSink = original;
    }

    function restoreDefaultSink(): void {
        root.disarmSwapRestore();
        const original = root.swappedSink;
        if (!original) return;
        root.swappedSink = "";
        Persistent.states.phone.mic.originalDefaultSink = "";
        root.run(["pactl", "set-default-sink", original], null);
    }

    // The swap has done its job the moment scrcpy's stream exists.
    function pollSwap(): void {
        root.run(["pactl", "list", "sink-inputs"], (text, code) => {
            if (root.streamPresent(text)) root.restoreDefaultSink();
        });
    }

    // Success is evidence, not a timer: the process is alive AND the null
    // sink reports a running input, which droidcam_status.sh answers.
    function verify(): void {
        root.run(["bash", root.statusScript], (text, code) => {
            if (!root.connecting) return;
            const status = root.parseStatus(text);
            if (status && status.audioRunning && status.audioHasSinkInput) {
                root.becomeActive();
            } else if (status && status.audioRunning) {
                if (root.connectDeadlinePassed())
                    root.fail("The phone microphone started but no audio reached the DroidCam-Mic sink - another audio processor may have claimed the stream");
                else root.armVerifyRetry();
            } else {
                root.fail("Phone microphone process exited - check the phone connection and that USB or Wireless debugging is still on");
            }
        });
    }

    function becomeActive(): void {
        root.connecting = false;
        root.active = true;
        root.lastError = "";
        root.startedAt = Math.floor(Date.now() / 1000);
        root.disarmConnectTimers();
        // The stream is on the null sink, so the swap has done its job even
        // if the poll never saw the sink-input appear.
        root.restoreDefaultSink();
        root.applyInitialState();
        root.armWatchdog();
    }

    function applyInitialState(): void {
        const conf = Config.options.phone.microphone;
        root.muted = false;
        root.gain = Number(conf.micGain) > 0 ? Number(conf.micGain) : 100;
        if (root.gain !== 100) root.setGain(root.gain);
        if (conf.setAsDefault) root.setAsDefaultInput();
    }

    function adoptSession(status: var): void {
        root.backend = status.session === "scrcpy-mic" ? "scrcpy" : "droidcam";
        root.sessionPid = status.pid;
        root.startedAt = status.started;
        root.activeMode = root.backend === "scrcpy" ? "scrcpy" : status.mode;
        root.activeIp = status.ip;
        root.activePort = status.port;
        root.run(["bash", root.setupScript], (text, code) => {
            root.pulseSource = (text ?? "").trim().split("\n")[0] ?? "";
            root.connecting = false;
            root.active = true;
            root.lastError = "";
            root.armWatchdog();
        });
    }

    // Boot: adopt a live session, and undo a swap the last shell left behind.
    function reconcile(): void {
        root.run(["bash", root.sessionScript, "status", "scrcpy-mic"], (scrcpyText, c1) => {
            const scrcpyStatus = root.parseSessionStatus(scrcpyText);
            root.run(["bash", root.sessionScript, "status", "audio"], (audioText, c2) => {
                const audioStatus = root.parseSessionStatus(audioText);
                const live = (scrcpyStatus && scrcpyStatus.alive) ? scrcpyStatus
                    : ((audioStatus && audioStatus.alive) ? audioStatus : null);
                if (live && !root.active && !root.connecting) root.adoptSession(live);
                root.run(["pactl", "get-default-sink"], (sinkText, c3) => {
                    const target = root.restorePlan(sinkText, Persistent.states.phone.mic.originalDefaultSink, live !== null);
                    if (!target) return;
                    root.swappedSink = "";
                    Persistent.states.phone.mic.originalDefaultSink = "";
                    root.run(["pactl", "set-default-sink", target], null);
                });
            });
        });
    }

    function checkSession(): void {
        root.run(["bash", root.sessionScript, "status", root.sessionFor(root.backend)], (text, code) => {
            const status = root.parseSessionStatus(text);
            if (status && status.alive) return;
            if (root.active) {
                root.active = false;
                root.disarmWatchdog();
                if (!root.userStopped) root.fail("Microphone connection lost - the audio process exited");
            }
        });
    }

    function cleanupSession(): void {
        root.run(["bash", root.sessionScript, "stop", "audio"], null);
        root.run(["bash", root.sessionScript, "stop", "scrcpy-mic"], null);
        root.run(["pactl", "unload-module", "module-loopback"], null);
        root.run(["bash", root.teardownScript], null);
        root.pulseSource = "";
        root.sessionPid = 0;
        root.startedAt = 0;
    }

    function stop(): void {
        if (!root.connecting && !root.active) return;
        root.userStopped = true;
        root.disarmConnectTimers();
        root.disarmWatchdog();
        if (root.isDefaultInput) root.restoreDefaultInput();
        root.restoreDefaultSink();
        root.connecting = false;
        root.active = false;
        root.muted = false;
        root.cleanupSession();
    }

    function toggle(): void {
        if (root.connecting || root.active) root.stop();
        else root.start();
    }

    function toggleMute(): void {
        root.muted = !root.muted;
        if (root.active && root.pulseSource)
            root.run(root.muteArgs(root.pulseSource, root.muted), null);
    }

    function setGain(percent: int): void {
        root.gain = Math.max(0, Math.min(200, percent));
        Config.options.phone.microphone.micGain = root.gain;
        if (root.active && root.pulseSource)
            root.run(root.gainArgs(root.pulseSource, root.gain), null);
    }

    function setAsDefaultInput(): void {
        if (!root.active || !root.pulseSource || root.isDefaultInput) return;
        root.run(["pactl", "get-default-source"], (text, code) => {
            const previous = (text ?? "").trim();
            if (!root.active || !root.pulseSource) return;
            root.previousDefaultSource = previous;
            root.isDefaultInput = true;
            root.run(["pactl", "set-default-source", root.pulseSource], null);
        });
    }

    function restoreDefaultInput(): void {
        if (!root.isDefaultInput) return;
        root.isDefaultInput = false;
        if (root.previousDefaultSource)
            root.run(["pactl", "set-default-source", root.previousDefaultSource], null);
        root.previousDefaultSource = "";
    }
    // END phone-mic logic

    // ---- timers ----

    property real connectStartedAt: 0

    function connectDeadlinePassed(): bool {
        return Date.now() - root.connectStartedAt >= root.connectTimeoutMs;
    }

    function armConnectTimers(): void {
        root.connectStartedAt = Date.now();
        failTimer.restart();
    }

    function disarmConnectTimers(): void {
        failTimer.stop();
        verifyTimer.stop();
        verifyRetryTimer.stop();
    }

    function armVerify(): void { verifyTimer.restart(); }
    function armVerifyRetry(): void { verifyRetryTimer.restart(); }

    function armSwapRestore(): void {
        swapTimer.elapsedMs = 0;
        swapTimer.restart();
    }

    function disarmSwapRestore(): void { swapTimer.stop(); }
    function armWatchdog(): void { watchdog.restart(); }
    function disarmWatchdog(): void { watchdog.stop(); }

    Timer {
        id: failTimer
        interval: root.connectTimeoutMs
        onTriggered: {
            if (!root.connecting) return;
            root.fail("Could not connect within " + Math.round(root.connectTimeoutMs / 1000)
                + "s - verify the phone is reachable and the DroidCam/scrcpy app is open");
        }
    }

    Timer {
        id: verifyTimer
        interval: root.verifyAfterMs
        onTriggered: if (root.connecting) root.verify()
    }

    Timer {
        id: verifyRetryTimer
        interval: 2000
        onTriggered: if (root.connecting) root.verify()
    }

    // Every millisecond past the stream's creation is silence on the user's
    // speakers, so the swap is polled rather than waited out.
    Timer {
        id: swapTimer
        property int elapsedMs: 0
        interval: root.swapPollMs
        repeat: true
        onTriggered: {
            swapTimer.elapsedMs += swapTimer.interval;
            if (swapTimer.elapsedMs >= root.swapCeilingMs) {
                swapTimer.stop();
                root.restoreDefaultSink();
                return;
            }
            root.pollSwap();
        }
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

    Component.onCompleted: root.reconcile()

    onActiveDeviceIdChanged: if (root.active || root.connecting) root.stop()
}
