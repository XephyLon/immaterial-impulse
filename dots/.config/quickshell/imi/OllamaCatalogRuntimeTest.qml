import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Drives OllamaCatalog against a fake daemon (tests/test_ollama_catalog_runtime.py
 * serves /api/tags, /api/ps, /api/pull and /api/delete on IMI_OLLAMA_URL):
 * the installed and loaded lists arrive, a pull streams progress to 1 and
 * lands in the installed list, a removal drops it, and the chat's model list
 * follows both. Nothing here touches a real daemon.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    property int step: 0
    property int discoveryWaited: 0
    property real maxFractionSeen: -1
    property var statusesSeen: []

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[OllamaCatalog] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[OllamaCatalog] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }
    function names() { return OllamaCatalog.installed.map(m => m.name); }

    Connections {
        target: OllamaCatalog
        function onPullFractionChanged() {
            if (OllamaCatalog.pullFraction > harness.maxFractionSeen) harness.maxFractionSeen = OllamaCatalog.pullFraction;
        }
        function onPullStatusChanged() {
            harness.statusesSeen = [...harness.statusesSeen, OllamaCatalog.pullStatus];
        }
    }

    Timer {
        id: driver
        interval: 250; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (harness.elapsed > 40000) { harness.check("finished in time", false); harness.finish(); return; }
            if (!Config.ready) return;
            switch (harness.step) {
            case 0:
                OllamaCatalog.watchers = 1;     // what the browse page does when shown
                harness.step = 1;
                break;
            case 1:
                if (OllamaCatalog.refreshing || !OllamaCatalog.daemonUp) return;
                harness.check("daemon detected through /api/tags", OllamaCatalog.daemonUp);
                harness.check("installed list carries the fake's two models with sizes",
                    harness.names().join(",") === "llama3.2:3b,nomic-embed-text:latest"
                    && OllamaCatalog.installed[0].size === 2019393189
                    && OllamaCatalog.installed[0].parameterSize === "3.2B");
                harness.check("loaded list comes from /api/ps", OllamaCatalog.running.length === 1 && OllamaCatalog.running[0] === "llama3.2:3b");
                harness.check("isInstalled answers with and without the :latest suffix",
                    OllamaCatalog.isInstalled("nomic-embed-text") && OllamaCatalog.isInstalled("llama3.2:3b") && !OllamaCatalog.isInstalled("qwen3:8b"));
                harness.check("disk free was measured", OllamaCatalog.diskFreeBytes > 0);
                harness.check("pull refuses an empty name", OllamaCatalog.pull("") !== "");
                // Process.running reports the start on the next turn, so
                // the synchronous evidence is the name the service took.
                harness.check("pull starts", OllamaCatalog.pull("qwen3:8b") === "" && OllamaCatalog.pullName === "qwen3:8b");
                harness.check("a second pull is refused while one runs", OllamaCatalog.pull("gemma3:4b") !== "");
                harness.step = 2;
                break;
            case 2:
                if (OllamaCatalog.pulling || OllamaCatalog.refreshing) return;
                harness.check("the pull streamed progress up to 1", harness.maxFractionSeen === 1);
                harness.check("the pull walked the daemon's statuses", harness.statusesSeen.indexOf("pulling manifest") !== -1 && harness.statusesSeen.indexOf("success") !== -1);
                harness.check("no pull error", OllamaCatalog.pullError === "");
                harness.check("the pulled model is installed now", OllamaCatalog.isInstalled("qwen3:8b"));
                // What the browse page does on pullFinished: re-run discovery.
                Ai.refreshOllamaModels();
                harness.discoveryWaited = 0;
                harness.step = 21;
                break;
            case 21:
                harness.discoveryWaited += interval;
                if (Ai.modelList.indexOf(Ai.safeModelName("qwen3:8b")) === -1 && harness.discoveryWaited < 8000) return;
                harness.check("chat discovery was refreshed and knows the model",
                    Ai.modelList.indexOf(Ai.safeModelName("qwen3:8b")) !== -1);
                OllamaCatalog.remove("qwen3:8b");
                harness.step = 3;
                break;
            case 3:
                if (OllamaCatalog.refreshing || OllamaCatalog.isInstalled("qwen3:8b")) return;
                harness.check("the removed model is gone from the daemon list", !OllamaCatalog.isInstalled("qwen3:8b"));
                Ai.forgetOllamaModel("qwen3:8b");
                harness.check("the chat forgets it at once", Ai.modelList.indexOf(Ai.safeModelName("qwen3:8b")) === -1);
                harness.finish();
                break;
            }
        }
    }
}
