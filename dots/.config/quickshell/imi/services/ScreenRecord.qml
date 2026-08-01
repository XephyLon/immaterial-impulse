pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import qs

/**
 * Screen recording on gpu-screen-recorder (ShadowPlay-style, GPU encode).
 *
 * Two independent capture paths:
 *  - One-shot recordings are owned by scripts/videos/record.sh (same script
 *    the keybinds and the region selector call); their state arrives through
 *    Persistent.states.record.enable, which the script maintains. This
 *    service only starts/stops/pauses them.
 *  - The instant-replay buffer is a persistent gpu-screen-recorder process
 *    owned here (-r ring buffer; SIGUSR1 dumps the last N seconds to a clip,
 *    the -sc hook notifies with the saved path). Enablement is the persisted
 *    config flag, so replay survives shell restarts.
 *
 * The two are separate gsr processes on purpose: replay must never die
 * because a one-shot recording was toggled, which is also why record.sh
 * scopes its stop-toggle with a pidfile instead of pkill by process name.
 */
Singleton {
    id: root

    readonly property var opts: Config.options.screenRecord

    // ---------------------------------------------------------------- record
    readonly property bool recording: Persistent.states.record.enable
    property bool recordPaused: false
    onRecordingChanged: {
        if (!recording) recordPaused = false
    }

    function toggleRecordScreen() {
        const args = [Directories.recordScriptPath, "--fullscreen"]
        if (root.opts.recordAudio) args.push("--sound")
        Quickshell.execDetached(args)
    }

    function stopRecord() {
        // record.sh toggles: with a live pidfile it just stops the recording.
        if (root.recording) Quickshell.execDetached([Directories.recordScriptPath])
    }

    function togglePauseRecord() {
        if (!root.recording) return
        pauseProc.running = true
        root.recordPaused = !root.recordPaused
    }
    Process {
        id: pauseProc
        // SIGUSR2 pauses/unpauses a regular gsr recording; scoped via the
        // record.sh pidfile so the replay daemon is never signalled.
        command: ["bash", "-c",
            `kill -USR2 "$(cat "\${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/imi-screenrecord.pid" 2>/dev/null)" 2>/dev/null`]
    }

    // ---------------------------------------------------------------- replay
    readonly property bool replaying: replayProc.running
    readonly property string replayDir: {
        const dir = (root.opts.replay.savePath || root.opts.savePath || "~/Videos").toString()
        return dir.startsWith("~") ? Directories.home.replace("file://", "") + dir.slice(1) : dir
    }

    function replayArgs() {
        const o = root.opts
        let args = ["gpu-screen-recorder",
            "-w", o.replay.monitor || "screen",
            "-r", `${Math.max(2, o.replay.duration)}`,
            "-replay-storage", o.replay.storage,
            "-restart-replay-on-save", o.replay.restartOnSave ? "yes" : "no",
            "-c", "mp4",
            "-f", `${o.fps}`,
            "-q", o.quality,
            "-ac", o.audioCodec,
            "-fm", o.framerateMode,
            "-cursor", o.showCursor ? "yes" : "no",
            "-sc", `${Directories.scriptPath}/videos/gsr-saved.sh`,
            "-o", root.replayDir]
        if (o.codec !== "auto") args.push("-k", o.codec)
        if (o.recordAudio) args.push("-a", o.recordMic ? "default_output|default_input" : "default_output")
        return args
    }

    function setReplayEnabled(enabled) {
        Config.options.screenRecord.replay.enable = enabled
    }
    function toggleReplay() {
        root.setReplayEnabled(!root.opts.replay.enable)
    }
    function saveReplay() {
        if (replayProc.running) replayProc.signal(10) // SIGUSR1: dump the buffer
    }

    Process {
        id: replayProc
        running: Config.ready && (root.opts.replay.enable ?? false)
        command: root.replayArgs()
        stderr: SplitParser {
            onRead: line => {
                if (line.includes("Error") || line.includes("error:"))
                    console.warn("[ScreenRecord] replay:", line)
            }
        }
        onExited: (exitCode, exitStatus) => {
            // One-shot on purpose (no respawn loop): a persistent failure -
            // missing binary, bad monitor - would otherwise spin. Flipping
            // the config toggle re-evaluates `running` and tries again.
            if (root.opts.replay.enable && exitCode !== 0) {
                console.warn("[ScreenRecord] replay daemon exited:", exitCode)
                Quickshell.execDetached(["notify-send", "Instant replay stopped",
                    `gpu-screen-recorder exited (${exitCode}). Toggle replay to retry.`,
                    "-a", "Recorder"])
                Config.options.screenRecord.replay.enable = false
            }
        }
    }

    GlobalShortcut {
        name: "screenRecordToggle"
        description: "Starts/stops a fullscreen recording"
        onPressed: {
            if (root.recording) root.stopRecord()
            else root.toggleRecordScreen()
        }
    }
    GlobalShortcut {
        name: "screenRecordPause"
        description: "Pauses/resumes the current recording"
        onPressed: root.togglePauseRecord()
    }
    GlobalShortcut {
        name: "replaySave"
        description: "Saves an instant-replay clip of the last moments"
        onPressed: root.saveReplay()
    }
    GlobalShortcut {
        name: "replayToggle"
        description: "Toggles the instant-replay buffer"
        onPressed: root.toggleReplay()
    }

    IpcHandler {
        target: "record"

        function toggleScreen(): void { root.toggleRecordScreen() }
        function stop(): void { root.stopRecord() }
        function pause(): void { root.togglePauseRecord() }
        function replayToggle(): void { root.toggleReplay() }
        function replaySave(): void { root.saveReplay() }
        function status(): string {
            return JSON.stringify({
                recording: root.recording,
                paused: root.recordPaused,
                replaying: root.replaying
            })
        }
    }
}
