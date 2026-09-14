import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Drives the launcher's Ask row in a real (nested) shell. With no usable
 * model an `@` query offers no row; with a keyless probe model injected the
 * way provider discovery injects one, the row appears under the prefix, a
 * long unmatched query gets it only with fallthrough on, a short one never,
 * and Enter (askAssistant) opens the Intelligence tab and sends exactly the
 * question. Launched by tests/test_launcher_ask_runtime.py.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    readonly property var search: LauncherSearch

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[LauncherAsk] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[LauncherAsk] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }
    function askRows() {
        return LauncherSearch.results.filter(r => r.verb === "Ask");
    }

    property int step: 0
    Timer {
        id: driver
        interval: 300; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (harness.elapsed > 40000) { harness.check("finished in time", false); harness.finish(); return; }
            if (!Config.ready) return;
            switch (harness.step) {
            case 0:
                Config.options.search.ai.fallthrough = false;
                LauncherSearch.query = "@what is a wayland compositor";
                harness.step = 1;
                break;
            case 1:
                harness.check("no usable model: no Ask row under the prefix", harness.askRows().length === 0);
                // A keyless model, injected the way ollama discovery does.
                Ai.models = Object.assign({}, Ai.models, {
                    "probe-model": { "name": "Probe", "icon": "ollama-symbolic", "model": "probe",
                        "requires_key": false, "api_format": "openai", "endpoint": "http://127.0.0.1:9/v1/chat/completions" }
                });
                // A fresh install may persist a model id that no longer
                // exists; select the probe the way the picker would.
                if (Persistent.states?.ai) Persistent.states.ai.model = "probe-model";
                console.log(`[LauncherAsk] current model: ${Ai.currentModelId} usable: ${Ai.currentModelHasApiKey}`);
                LauncherSearch.query = "";
                LauncherSearch.query = "@what is a wayland compositor";
                harness.step = 2;
                break;
            case 2: {
                const rows = harness.askRows();
                harness.check("usable model: exactly one Ask row under the prefix, first",
                    rows.length === 1 && LauncherSearch.results[0] === rows[0]);
                harness.check("the row carries the question without the prefix and names the model",
                    rows.length === 1 && rows[0].name === "what is a wayland compositor" && rows[0].type.includes("Probe"));
                LauncherSearch.query = "zzqx quorvat plimbrex nothing matches this";
                harness.step = 3;
                break;
            }
            case 3:
                harness.check("fallthrough off: a long unmatched query gets no Ask row", harness.askRows().length === 0);
                Config.options.search.ai.fallthrough = true;
                LauncherSearch.query = "";
                LauncherSearch.query = "zzqx quorvat plimbrex nothing matches this";
                harness.step = 4;
                break;
            case 4: {
                const rows = harness.askRows();
                const results = LauncherSearch.results;
                const idx = results.indexOf(rows[0]);
                const afterIt = results.slice(idx + 1);
                harness.check("fallthrough on: the long unmatched query gets one Ask row",
                    rows.length === 1);
                harness.check("the fallthrough row sits before only the default command/math/web rows",
                    rows.length === 1 && afterIt.every(r => ["Command", "Web search", "Math", "Calculate"].some(t => r.type.includes(t)) || r.verb === "Search" || r.verb === "Run"));
                LauncherSearch.query = "zzqx plim";
                harness.step = 5;
                break;
            }
            case 5:
                harness.check("fallthrough on: a short query gets no Ask row", harness.askRows().length === 0);
                harness.check("nothing was sent while typing", Ai.messageIDs.length === 0);
                harness.step = 6;
                // The probe model has no real endpoint; the request the send
                // starts may fail loudly, which is not what this measures.
                try { LauncherSearch.askAssistant("probe question"); } catch (e) { console.log(`[LauncherAsk] askAssistant threw: ${e}`); }
                break;
            case 6: {
                const first = Ai.messageIDs.length > 0 ? Ai.messageByID[Ai.messageIDs[0]] : null;
                harness.check("askAssistant opens the left sidebar on the Intelligence tab",
                    GlobalStates.sidebarLeftOpen === true && GlobalStates.overviewOpen === false);
                harness.check("askAssistant sends exactly the question as the user",
                    first !== null && first.role === "user" && first.rawContent === "probe question");
                driver.running = false;
                harness.finish();
                break;
            }
            }
        }
    }
}
