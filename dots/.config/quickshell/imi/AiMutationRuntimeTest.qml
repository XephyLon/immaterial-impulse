import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * The reviewed tier inside a real (nested) shell: a reviewed tool call
 * raises the approval card (functionPending, a mutation fence with the
 * summary) and changes nothing; reject answers the model and changes
 * nothing; approve applies it (a to-do appears, a file is written with its
 * .bak, a palette source is set) and answers the model; an invalid call is
 * refused without a card. Launched by tests/test_ai_mutation_runtime.py
 * with a probe folder in IMI_AI_MUTATION_PROBE_DIR.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    property int step: 0
    readonly property string probeDir: Quickshell.env("IMI_AI_MUTATION_PROBE_DIR") ?? ""
    readonly property var keep: Ai

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[Mutation] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[Mutation] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }
    function outputsOf(name) {
        return Ai.messageIDs.map(id => Ai.messageByID[id]).filter(m => m && m.functionName === name && m.role === "user")
            .map(m => String(m.functionResponse ?? ""));
    }
    // A pretend assistant message carrying the tool call, the way the stream
    // hands one to handleFunctionCall. Minted through Ai's own addMessage:
    // calling Component.createObject (an overloaded C++ method) from this
    // context made Qt 6.11 segfault in QObjectMethod::resolveOverloaded.
    function newAssistantMessage() {
        // Non-empty on purpose: addMessage drops an empty message, and the
        // "last id" would then be the previous tool's output.
        Ai.addMessage("(tool call)", "assistant");
        const id = Ai.messageIDs[Ai.messageIDs.length - 1];
        const m = Ai.messageByID[id];
        if (!m || m.role !== "assistant") console.log("[Mutation] harness: minted message is not an assistant message");
        return m;
    }

    property var pending: null
    Timer {
        id: driver
        interval: 250; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (harness.elapsed > 40000) { harness.check("finished in time", false); harness.finish(); return; }
            if (!Config.ready) return;
            switch (harness.step) {
            case 0: {
                Config.options.ai.tools.folders = [harness.probeDir];
                const before = (Todo.list ?? []).length;
                harness.todoBefore = before;
                const m = harness.newAssistantMessage();
                Ai.handleFunctionCall("add_todo", { "text": "probe item" }, m);
                harness.check("a reviewed call raises the card and changes nothing",
                    m.functionPending === true && m.content.includes("```mutation") && m.content.includes("probe item")
                    && (Todo.list ?? []).length === before && harness.outputsOf("add_todo").length === 0);
                Ai.rejectCommand(m);
                harness.check("reject answers the model and still changes nothing",
                    m.functionPending === false && harness.outputsOf("add_todo").length === 1
                    && harness.outputsOf("add_todo")[0].includes("rejected") && (Todo.list ?? []).length === before);
                const m2 = harness.newAssistantMessage();
                Ai.handleFunctionCall("add_todo", { "text": "probe item" }, m2);
                Ai.approveCommand(m2);
                harness.step = 1;
                break;
            }
            case 1:
                if ((Todo.list ?? []).length <= harness.todoBefore) return;
                harness.check("approve applies the change and answers the model",
                    (Todo.list ?? []).some(t => t.content === "probe item") && harness.outputsOf("add_todo").length === 2);
                // A file write: card, then approve, then the file and its .bak.
                harness.pending = harness.newAssistantMessage();
                Ai.handleFunctionCall("write_file", { "path": harness.probeDir + "/note.md", "content": "rewritten by the assistant\n" }, harness.pending);
                harness.check("write_file raises the card with the path in the summary",
                    harness.pending.functionPending === true && harness.pending.content.includes("note.md"));
                Ai.approveCommand(harness.pending);
                harness.step = 2;
                break;
            case 2:
                if (harness.outputsOf("write_file").length === 0) return;
                harness.check("the approved write answered with the path and the backup",
                    harness.outputsOf("write_file")[0].includes("Wrote") && harness.outputsOf("write_file")[0].includes(".bak"));
                // An invalid call: no card, a refusal.
                const m3 = harness.newAssistantMessage();
                Ai.handleFunctionCall("set_color_scheme", {}, m3);
                harness.check("a call missing its required argument is refused without a card",
                    m3.functionPending === false && harness.outputsOf("set_color_scheme").length === 1
                    && harness.outputsOf("set_color_scheme")[0].includes("Missing"));
                // A palette source change, approved: config follows.
                const m4 = harness.newAssistantMessage();
                Ai.handleFunctionCall("set_palette_source", { "mode": "saturation" }, m4);
                Ai.approveCommand(m4);
                harness.check("an approved palette source lands in the config",
                    Config.options.appearance.palette.sourceMode === "saturation" && harness.outputsOf("set_palette_source").length === 1);
                // A write outside the allowlist, approved, is still refused by the fence.
                harness.pending = harness.newAssistantMessage();
                Ai.handleFunctionCall("write_file", { "path": "/etc/motd", "content": "no" }, harness.pending);
                Ai.approveCommand(harness.pending);
                harness.step = 3;
                break;
            case 3:
                if (harness.outputsOf("write_file").length < 2) return;
                harness.check("an approved write outside the allowlist is refused by the fence",
                    harness.outputsOf("write_file")[1].startsWith("Refused:"));
                harness.finish();
                break;
            }
        }
    }
    property int todoBefore: 0
}
