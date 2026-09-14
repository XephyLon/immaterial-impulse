import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Drives the assistant's read-tier tools through Ai.handleFunctionCall the
 * way a model's tool call would arrive, inside a real (nested) shell: the
 * synchronous ones answer at once, the file ones answer through the fenced
 * script and continue the chat afterwards. Launched by
 * tests/test_ai_tools_runtime.py with a throwaway XDG home and a probe
 * folder in IMI_AI_TOOLS_PROBE_DIR holding note.md and .secret.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    readonly property string probeDir: Quickshell.env("IMI_AI_TOOLS_PROBE_DIR") ?? ""
    // Keep the singleton alive - nothing else in this harness references it.
    readonly property var ai: Ai

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[AiTools] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[AiTools] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }
    // Every function-output message a given tool produced, oldest first.
    function outputsOf(name) {
        return Ai.messageIDs.map(id => Ai.messageByID[id])
            .filter(m => m && m.functionName === name)
            .map(m => String(m.functionResponse ?? ""));
    }

    Timer {
        id: waitForConfig
        interval: 50; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (!Config.ready) {
                if (harness.elapsed >= 15000) { harness.check("config ready", false); harness.finish(); }
                return;
            }
            waitForConfig.running = false;
            Config.options.ai.tools.folders = [harness.probeDir];
            Config.options.ai.tools.allowClipboard = true;
            // Synchronous tools.
            Ai.handleFunctionCall("list_todos", {}, null);
            Ai.handleFunctionCall("get_wallpaper", {}, null);
            Ai.handleFunctionCall("get_clipboard", {}, null);
            Ai.handleFunctionCall("list_events", { "days": 7 }, null);
            // Asynchronous file tools, one after another (one at a time).
            Ai.handleFunctionCall("read_file", { "path": harness.probeDir + "/note.md" }, null);
            chain.step = 1;
            chain.running = true;
        }
    }

    Timer {
        id: chain
        property int step: 0
        interval: 250; repeat: true
        onTriggered: {
            harness.elapsed += interval;
            if (harness.elapsed > 40000) { harness.check("file tools answered in time", false); harness.finish(); return; }
            if (chain.step === 1 && harness.outputsOf("read_file").length >= 1) {
                Ai.handleFunctionCall("read_file", { "path": harness.probeDir + "/.secret" }, null);
                chain.step = 2;
            } else if (chain.step === 2 && harness.outputsOf("read_file").length >= 2) {
                Ai.handleFunctionCall("read_file", { "path": "/etc/passwd" }, null);
                chain.step = 3;
            } else if (chain.step === 3 && harness.outputsOf("read_file").length >= 3) {
                Ai.handleFunctionCall("list_directory", { "path": harness.probeDir, "depth": 1 }, null);
                chain.step = 4;
            } else if (chain.step === 4 && harness.outputsOf("list_directory").length >= 1) {
                chain.running = false;
                harness.evaluate();
            }
        }
    }

    function evaluate() {
        const todos = harness.outputsOf("list_todos");
        harness.check("list_todos answered", todos.length === 1 && todos[0].length > 0);
        const wall = harness.outputsOf("get_wallpaper");
        harness.check("get_wallpaper reports mode and palette",
            wall.length === 1 && wall[0].includes("Mode: ") && wall[0].includes("Palette: type="));
        const clip = harness.outputsOf("get_clipboard");
        harness.check("get_clipboard answered", clip.length === 1 && clip[0].length > 0);
        const events = harness.outputsOf("list_events");
        harness.check("list_events answered", events.length === 1 && events[0].length > 0);
        const reads = harness.outputsOf("read_file");
        harness.check("read_file returns the allowed file in a data block",
            reads.length === 3 && reads[0].includes("BEGIN FILE CONTENT") && reads[0].includes("probe note body"));
        harness.check("read_file refuses a dotfile inside the allowlist",
            reads.length === 3 && reads[1].startsWith("Refused:") && reads[1].includes("Hidden"));
        harness.check("read_file refuses a path outside the allowlist",
            reads.length === 3 && reads[2].startsWith("Refused:") && reads[2].includes("outside"));
        const lists = harness.outputsOf("list_directory");
        harness.check("list_directory lists note.md and hides .secret",
            lists.length === 1 && lists[0].includes("f note.md") && !lists[0].includes(".secret"));
        harness.finish();
    }
}
