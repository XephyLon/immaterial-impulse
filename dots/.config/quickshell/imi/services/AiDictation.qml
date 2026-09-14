pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Dictation for the assistant (docs/proposals/ai-voice-input.md): press to
 * listen, press to stop, the transcript lands in the composer's draft.
 *
 * States: idle -> listening -> transcribing -> idle. The recording and the
 * transcription are scripts/ai/ai_dictate.py; this owns the state, the
 * watchdog (ai.dictation.maxSeconds), the draft hand-off (AiDrafts, so a
 * transcript taken with the sidebar closed is there when it opens) and the
 * optional auto-send. The privacy indicator lights for the whole recording
 * because a process really holds the microphone - that is the honest
 * behaviour, not something to hide.
 */
Singleton {
    id: root

    readonly property string engine: Config.options?.ai?.dictation?.engine ?? "local"
    readonly property string model: Config.options?.ai?.dictation?.model ?? "base"
    readonly property bool autoSend: Config.options?.ai?.dictation?.autoSend ?? false
    readonly property int maxSeconds: Config.options?.ai?.dictation?.maxSeconds ?? 60
    readonly property string providerKeyId: Config.options?.ai?.dictation?.providerKeyId ?? "openai"
    readonly property string script: `${Directories.scriptPath}/ai/ai_dictate.py`.replace(/^file:\/\//, "")

    property string state: "idle"   // idle | listening | transcribing
    property int seconds: 0
    property string lastText: ""
    property string lastError: ""
    readonly property bool listening: root.state === "listening"
    readonly property bool busy: root.state !== "idle"

    // What the probe found. `available` is what the chip and the settings
    // row read; `hint` says what to install when it is false.
    property bool probed: false
    property bool recorderPresent: false
    property bool fasterWhisper: false
    property string whisperCli: ""
    property string whisperCppModel: ""
    readonly property bool localAvailable: root.recorderPresent && (root.fasterWhisper || (root.whisperCli.length > 0 && root.whisperCppModel.length > 0))
    readonly property bool available: root.recorderPresent && (root.engine === "provider" ? true : root.localAvailable)
    readonly property string hint: !root.recorderPresent
        ? Translation.tr("No recorder found: install PipeWire's pw-record or pulseaudio's parec")
        : (root.engine === "local" && !root.localAvailable)
            ? Translation.tr("No local transcriber: install faster-whisper into the shell's venv (uv pip install faster-whisper), then download a model")
            : ""

    signal transcribed(string text)
    signal failed(string error)

    function probe() { if (!probeProc.running) probeProc.running = true; }

    function dictate(action) {
        const a = String(action ?? "toggle");
        if (a === "start") root.start();
        else if (a === "stop") root.stop();
        else root.toggle();
    }
    function toggle() {
        if (root.state === "listening") root.stop();
        else if (root.state === "idle") root.start();
    }
    function start() {
        if (root.state !== "idle" || startProc.running) return;
        root.lastError = "";
        root.state = "listening";
        root.seconds = 0;
        startProc.command = ["python3", root.script, "start"];
        startProc.running = true;
    }
    function stop() {
        if (root.state !== "listening" || stopProc.running) return;
        root.state = "transcribing";
        tick.stop();
        stopProc.environment = ({});
        if (root.engine === "provider")
            stopProc.environment = ({ "API_KEY": Ai.apiKeys?.[root.providerKeyId] ?? "" });
        stopProc.command = ["python3", root.script, "stop", "--engine", root.engine, "--model", root.model];
        stopProc.running = true;
    }
    function download() {
        if (downloadProc.running) return;
        root.downloadState = "downloading";
        downloadProc.command = ["python3", root.script, "download", "--model", root.model];
        downloadProc.running = true;
    }
    property string downloadState: ""   // "" | downloading | done | error

    // The recording clock and the watchdog: a stuck keybind never records
    // past maxSeconds.
    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.seconds++;
            if (root.seconds >= root.maxSeconds) root.stop();
        }
    }

    function _fail(error) {
        root.state = "idle";
        root.lastError = String(error);
        root.failed(root.lastError);
    }

    Process {
        id: probeProc
        // A capability probe starts itself (tests/lint_capability_probe_gating.py):
        // the chip and the settings row read it before anyone dictates.
        running: true
        command: ["python3", `${Directories.scriptPath}/ai/ai_dictate.py`.replace(/^file:\/\//, ""), "probe"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const p = JSON.parse(String(text).trim());
                    root.recorderPresent = !!p.recorder;
                    root.fasterWhisper = p.faster_whisper === true;
                    root.whisperCli = p.whisper_cli ?? "";
                    root.whisperCppModel = p.whisper_cpp_model ?? "";
                } catch (e) { /* no python, no dictation */ }
                root.probed = true;
            }
        }
    }
    Process {
        id: startProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(String(text).trim());
                    if (r.ok) { tick.restart(); return; }
                    root._fail(r.error ?? "could not start recording");
                } catch (e) { root._fail("could not start recording"); }
            }
        }
    }
    Process {
        id: stopProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null;
                try { r = JSON.parse(String(text).trim()); } catch (e) { r = null; }
                if (!r || !r.ok) { root._fail(r?.error ?? "transcription failed"); return; }
                root.state = "idle";
                root.lastText = String(r.text ?? "").trim();
                if (root.lastText.length === 0) { root._fail(Translation.tr("Nothing was heard")); return; }
                // The draft first, so a transcript taken with the sidebar
                // closed is there when it opens; the composer re-reads it on
                // the signal.
                const key = AiSessions.currentId;
                const existing = String(AiDrafts.take(key) ?? "").trim();
                const merged = existing.length > 0 ? existing + " " + root.lastText : root.lastText;
                if (root.autoSend) {
                    AiDrafts.clear(key);
                    Ai.sendUserMessage(merged);
                } else {
                    AiDrafts.record(key, merged);
                }
                root.transcribed(root.lastText);
            }
        }
    }
    Process {
        id: downloadProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(String(text).trim());
                    root.downloadState = r.ok ? "done" : "error";
                    if (!r.ok) root.lastError = String(r.error ?? "download failed");
                } catch (e) { root.downloadState = "error"; }
                root.probe();
            }
        }
    }
}
