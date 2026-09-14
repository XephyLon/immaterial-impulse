import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Drives dictation end to end in a nested shell, with a stub `pw-record` on
 * PATH and IMI_DICTATE_FAKE_TRANSCRIPT standing in for the transcriber
 * (tests/test_ai_dictation_runtime.py): start -> listening with a running
 * clock, stop -> transcribing -> idle with the text in the draft and the
 * transcribed() signal; the watchdog stops a recording at maxSeconds; a
 * second take appends to the draft; auto-send sends instead.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    property int step: 0
    property int transcribedCount: 0
    property string lastTranscribed: ""
    readonly property var keep: AiDictation

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[Dictation] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[Dictation] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }
    Connections {
        target: AiDictation
        function onTranscribed(text) { harness.transcribedCount++; harness.lastTranscribed = text; }
    }

    Timer {
        id: driver
        interval: 200; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (harness.elapsed > 60000) { harness.check("finished in time", false); harness.finish(); return; }
            if (!Config.ready || !AiDictation.probed) return;
            switch (harness.step) {
            case 0:
                Config.options.ai.dictation.engine = "local";
                Config.options.ai.dictation.autoSend = false;
                Config.options.ai.dictation.maxSeconds = 60;
                harness.check("the probe saw the (stub) recorder", AiDictation.recorderPresent === true);
                harness.check("without a transcriber the local engine is unavailable and says what to install",
                    AiDictation.available === false && AiDictation.hint.includes("faster-whisper"));
                AiDictation.start();
                harness.check("start enters listening at once", AiDictation.state === "listening");
                harness.step = 1;
                break;
            case 1:
                if (harness.elapsed < 2600) return;
                harness.check("the clock runs while listening", AiDictation.seconds >= 1);
                AiDictation.stop();
                harness.check("stop enters transcribing", AiDictation.state === "transcribing");
                harness.step = 2;
                break;
            case 2:
                if (AiDictation.state !== "idle") return;
                harness.check("the fake transcript arrived through the signal", harness.transcribedCount === 1 && harness.lastTranscribed === "hello from the fake transcriber");
                harness.check("the transcript is in the draft, not sent", AiDrafts.take(AiSessions.currentId) === "hello from the fake transcriber" && Ai.messageIDs.length === 0);
                // A second take appends.
                AiDictation.start();
                harness.step = 3;
                break;
            case 3:
                if (AiDictation.state !== "listening" || harness.elapsed % 1000 !== 0) return;
                AiDictation.stop();
                harness.step = 4;
                break;
            case 4:
                if (AiDictation.state !== "idle") return;
                harness.check("a second take appends to the draft", AiDrafts.take(AiSessions.currentId) === "hello from the fake transcriber hello from the fake transcriber");
                // The watchdog.
                AiDrafts.clear(AiSessions.currentId);
                Config.options.ai.dictation.maxSeconds = 2;
                AiDictation.start();
                harness.watchdogStart = harness.elapsed;
                harness.step = 5;
                break;
            case 5:
                if (AiDictation.state === "listening" && harness.elapsed - harness.watchdogStart < 6000) return;
                harness.check("the watchdog stopped the recording at maxSeconds", AiDictation.state !== "listening" && harness.elapsed - harness.watchdogStart <= 4000);
                harness.step = 6;
                break;
            case 6:
                if (AiDictation.state !== "idle") return;
                harness.check("the watchdog's take was transcribed too", harness.transcribedCount === 3);
                // Auto-send.
                Config.options.ai.dictation.maxSeconds = 60;
                Config.options.ai.dictation.autoSend = true;
                AiDrafts.clear(AiSessions.currentId);
                AiDictation.start();
                harness.step = 7;
                break;
            case 7:
                if (AiDictation.state !== "listening" || harness.elapsed % 1000 !== 0) return;
                AiDictation.stop();
                harness.step = 8;
                break;
            case 8: {
                if (AiDictation.state !== "idle") return;
                const first = Ai.messageIDs.length > 0 ? Ai.messageByID[Ai.messageIDs[0]] : null;
                harness.check("auto-send sent the transcript as the user", first !== null && first.role === "user" && first.rawContent === "hello from the fake transcriber");
                harness.check("auto-send left no draft behind", String(AiDrafts.take(AiSessions.currentId) ?? "") === "");
                harness.finish();
                break;
            }
            }
        }
    }
    property int watchdogStart: 0
}
