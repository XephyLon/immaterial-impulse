import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Drives local retrieval end to end inside a real (nested) shell: a probe
 * folder in IMI_AI_RAG_PROBE_DIR is configured, AiRag.index() runs the
 * script with the offline embedder, search_documents through
 * Ai.handleFunctionCall answers with the matching passage in a data block
 * and stamps citation sources for the next reply, and the Documents toggle
 * path rides the passages in the wire content while the bubble keeps the
 * typed text. Launched by tests/test_ai_rag_runtime.py.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    property int step: 0
    readonly property string probeDir: Quickshell.env("IMI_AI_RAG_PROBE_DIR") ?? ""
    readonly property var ai: Ai

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[AiRag] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[AiRag] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }
    function outputsOf(name) {
        return Ai.messageIDs.map(id => Ai.messageByID[id]).filter(m => m && m.functionName === name)
            .map(m => String(m.functionResponse ?? ""));
    }

    Timer {
        id: driver
        interval: 250; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (harness.elapsed > 60000) { harness.check("finished in time", false); harness.finish(); return; }
            if (!Config.ready) return;
            switch (harness.step) {
            case 0:
                harness.check("nothing configured: search_documents says where to configure", true);
                Ai.handleFunctionCall("search_documents", { "query": "compositor" }, null);
                harness.step = 1;
                break;
            case 1: {
                const outs = harness.outputsOf("search_documents");
                if (outs.length === 0) return;
                harness.check("unconfigured answer names Settings", outs[0].includes("Settings"));
                Config.options.ai.documents.folders = [harness.probeDir];
                Config.options.ai.documents.embedder = "lexical";
                harness.check("configured once a folder is named", AiRag.configured === true);
                AiRag.index();
                harness.step = 2;
                break;
            }
            case 2:
                if (AiRag.indexing || AiRag.status === "indexing") return;
                harness.check("index finished without error", AiRag.status === "idle" && AiRag.error === "");
                harness.check("index counted the probe files", AiRag.files === 2 && AiRag.chunks >= 2);
                Ai.handleFunctionCall("search_documents", { "query": "wayland compositor framebuffer", "k": 3 }, null);
                harness.step = 3;
                break;
            case 3: {
                const outs = harness.outputsOf("search_documents");
                if (outs.length < 2) return;
                const answer = outs[1];
                harness.check("the tool returns the matching passage in a labelled data block",
                    answer.includes("BEGIN RETRIEVED DOCUMENTS") && answer.includes("framebuffer") && answer.includes("wayland.md:"));
                harness.check("the passage from the other file ranks below or is absent",
                    answer.indexOf("wayland.md") < (answer.indexOf("recipes.txt") === -1 ? Infinity : answer.indexOf("recipes.txt")));
                harness.check("citation sources are queued for the reply",
                    Ai.pendingRagSources.length >= 1 && String(Ai.pendingRagSources[0].url).startsWith("file://")
                    && String(Ai.pendingRagSources[0].text).startsWith("wayland.md:"));
                // The Documents toggle path.
                Config.options.ai.documents.alwaysAttach = true;
                Ai.sendUserMessage("what does a compositor draw into?");
                harness.step = 4;
                break;
            }
            case 4: {
                const user = Ai.messageIDs.map(id => Ai.messageByID[id]).filter(m => m && m.role === "user" && !m.functionName).pop();
                if (!user || !String(user.rawContent).includes("RETRIEVED")) { if (harness.elapsed > 50000) { harness.check("always-attach retrieved in time", false); harness.finish(); } return; }
                harness.check("the bubble keeps the typed text", user.content === "what does a compositor draw into?");
                harness.check("the wire content carries the passages", user.rawContent.includes("BEGIN RETRIEVED DOCUMENTS") && user.rawContent.includes("framebuffer"));
                harness.finish();
                break;
            }
            }
        }
    }
}
