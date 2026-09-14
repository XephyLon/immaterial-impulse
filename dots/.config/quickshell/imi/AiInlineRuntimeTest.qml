import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Inline answers in a real (nested) shell against a fake OpenAI-compatible
 * server (IMI_AI_INLINE_PROBE_URL). Off: nothing is sent. On, with a
 * loopback model: a burst of keystrokes yields one request after the pause,
 * the answer lands on AiInline for that question, a short query never asks,
 * a long answer is cut at maxChars. A remote model asks nothing until the
 * cloud switch is on. Enter with an answer puts question and answer in the
 * chat without a request. Closing the overview cancels.
 * Launched by tests/test_ai_inline_runtime.py, which counts the requests.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    property int step: 0
    property int waited: 0
    property bool sawBusy: false
    readonly property string probeUrl: Quickshell.env("IMI_AI_INLINE_PROBE_URL") ?? ""
    readonly property var keep: [LauncherSearch, AiInline]

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[AiInline] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[AiInline] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }
    function askRows() { return LauncherSearch.results.filter(r => r.verb === "Ask"); }
    // Through Ai.addModel, the way discovery adds one: the strategies take
    // a typed AiModel, and a plain object injected into Ai.models coerces
    // to null there (the request then dies with "Cannot read property
    // 'endpoint' of null" and nothing is sent).
    function useModel(endpoint) {
        Ai.addModel("probe-model", { "name": "Probe", "icon": "ollama-symbolic", "model": "probe",
            "requires_key": false, "api_format": "openai", "endpoint": endpoint });
        if (Persistent.states?.ai) Persistent.states.ai.model = "probe-model";
    }
    // A burst of keystrokes ending in the full question.
    function type(question) {
        LauncherSearch.query = "";
        LauncherSearch.query = "@" + question.slice(0, question.length - 3);
        LauncherSearch.query = "@" + question.slice(0, question.length - 1);
        LauncherSearch.query = "@" + question;
    }
    // Wait up to `ms` (in ticks) for `cond`; returns true once it holds, and
    // false when the time is up (the caller checks whichever it meant).
    function waitFor(cond, ms) {
        if (cond()) { harness.waited = 0; return true; }
        harness.waited += driver.interval;
        if (harness.waited < ms) return null;
        harness.waited = 0;
        return false;
    }

    Timer {
        id: driver
        interval: 100; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (AiInline.busy) harness.sawBusy = true;
            if (harness.elapsed > 60000) { harness.check("finished in time", false); harness.finish(); return; }
            if (!Config.ready) return;
            switch (harness.step) {
            case 0:
                Config.options.search.ai.fallthrough = false;
                Config.options.search.ai.inline = false;
                Config.options.search.ai.inlineWithCloud = false;
                Config.options.search.ai.inlineDelayMs = 400;
                harness.useModel(harness.probeUrl);
                harness.type("what is a wayland compositor");
                harness.step = 1;
                break;
            case 1: {
                const r = harness.waitFor(() => false, 1500);
                if (r === null) return;
                harness.check("inline off: nothing asked, no answer",
                    !AiInline.busy && !harness.sawBusy && AiInline.answer === "" && AiInline.question === "");
                harness.check("the Ask row is there regardless", harness.askRows().length === 1);
                Config.options.search.ai.inline = true;
                harness.type("what is a wayland compositor");
                harness.check("a keystroke arms the debounce, not a request",
                    AiInline.question === "what is a wayland compositor" && !AiInline.busy && AiInline.answer === "");
                harness.step = 2;
                break;
            }
            case 2: {
                const r = harness.waitFor(() => AiInline.done, 8000);
                if (r === null) return;
                harness.check("inline on, loopback model: the answer lands after the pause",
                    r === true && AiInline.answer.startsWith("A Wayland compositor") && AiInline.question === "what is a wayland compositor");
                harness.check("the results list still has exactly one Ask row, first",
                    harness.askRows().length === 1 && LauncherSearch.results[0].id === "ask-assistant");
                harness.check("nothing reached the chat", Ai.messageIDs.length === 0);
                harness.sawBusy = false;
                harness.type("hi there");
                harness.step = 3;
                break;
            }
            case 3: {
                const r = harness.waitFor(() => false, 1200);
                if (r === null) return;
                harness.check("a short question is never asked", !harness.sawBusy && AiInline.answer === "" && AiInline.question === "");
                harness.type("tell me something longwinded please");
                harness.step = 4;
                break;
            }
            case 4: {
                const r = harness.waitFor(() => AiInline.done, 8000);
                if (r === null) return;
                harness.check("a long answer is cut at maxChars with an ellipsis",
                    r === true && AiInline.answer.length <= AiInline.maxChars + 1 && AiInline.answer.endsWith("…"));
                // A remote model: the cloud switch gates it.
                harness.useModel("http://example.invalid:1/v1/chat/completions");
                harness.sawBusy = false;
                harness.type("what is a wayland compositor");
                harness.step = 5;
                break;
            }
            case 5: {
                const r = harness.waitFor(() => false, 1200);
                if (r === null) return;
                harness.check("a remote model without the cloud switch asks nothing",
                    !harness.sawBusy && AiInline.answer === "" && !AiInline.allowed);
                Config.options.search.ai.inlineWithCloud = true;
                harness.type("what is a wayland compositor");
                harness.step = 6;
                break;
            }
            case 6: {
                const r = harness.waitFor(() => harness.sawBusy, 3000);
                if (r === null) return;
                harness.check("with the cloud switch the request is attempted", r === true);
                Config.options.search.ai.inlineWithCloud = false;
                harness.useModel(harness.probeUrl);
                harness.type("what is a wayland compositor");
                harness.step = 7;
                break;
            }
            case 7: {
                const r = harness.waitFor(() => AiInline.done, 8000);
                if (r === null) return;
                const answer = AiInline.answer;
                // The real order: the row's activated() closes the overview
                // (LauncherSearch cancels AiInline on that) BEFORE execute()
                // reaches askAssistant. The answer must survive that.
                GlobalStates.overviewOpen = true;
                GlobalStates.overviewOpen = false;
                harness.check("closing the overview parks the answer for Enter",
                    AiInline.answer === "" && !AiInline.busy && AiInline.lastAnswer === answer);
                LauncherSearch.askAssistant("what is a wayland compositor");
                const msgs = Ai.messageIDs.map(id => Ai.messageByID[id]);
                harness.check("Enter with an answer: question and answer land in the chat, no request",
                    msgs.length === 2 && msgs[0].role === "user" && msgs[0].rawContent === "what is a wayland compositor"
                    && msgs[1].role === "assistant" && msgs[1].rawContent === answer && answer.length > 0 && !Ai.isGenerating
                    && msgs[1].model === Ai.currentModelId);
                harness.check("Enter opens the Intelligence tab and closes the overview",
                    GlobalStates.sidebarLeftOpen === true && GlobalStates.overviewOpen === false);
                harness.check("the answer was taken: AiInline is clear", AiInline.answer === "" && AiInline.question === "" && AiInline.lastAnswer === "");
                GlobalStates.overviewOpen = true;
                harness.type("what is a wayland compositor");
                harness.step = 8;
                break;
            }
            case 8:
                harness.check("a new question is pending again", AiInline.question === "what is a wayland compositor");
                GlobalStates.overviewOpen = false;
                harness.check("closing the overview cancels it",
                    AiInline.question === "" && AiInline.answer === "" && !AiInline.busy);
                driver.running = false;
                harness.finish();
                break;
            }
        }
    }
}
