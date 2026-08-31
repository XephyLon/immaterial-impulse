import QtTest
import "../services/ai/prompt_history.js" as PromptHistory

// Shell-style prompt recall as a fold: the composer holds {index, backup}
// and applies step() per keypress. Pure, so every rule the spec states is
// checked here and the composer only wires keys.
TestCase {
    name: "PromptHistoryTest"

    readonly property var history: ["first", "second", "third"]

    function test_idle_down_is_unhandled() {
        const r = PromptHistory.step(PromptHistory.idle(), history, "draft", 1);
        verify(!r.handled);
    }

    function test_empty_history_is_unhandled() {
        const r = PromptHistory.step(PromptHistory.idle(), [], "", -1);
        verify(!r.handled);
    }

    function test_up_from_idle_backs_up_the_draft_and_lands_newest() {
        const r = PromptHistory.step(PromptHistory.idle(), history, "half a thought", -1);
        verify(r.handled);
        compare(r.index, 2);
        compare(r.backup, "half a thought");
        compare(r.text, "third");
    }

    function test_walk_up_and_oldest_consumes_further_ups() {
        let s = PromptHistory.step(PromptHistory.idle(), history, "", -1);
        s = PromptHistory.step(s, history, history[s.index], -1);
        compare(s.text, "second");
        s = PromptHistory.step(s, history, history[s.index], -1);
        compare(s.text, "first");
        const stuck = PromptHistory.step(s, history, "first", -1);
        verify(stuck.handled, "the key is consumed at the oldest");
        compare(stuck.index, 0);
        compare(stuck.text, null, "no rewrite when nothing moves");
    }

    function test_down_past_newest_restores_the_draft_and_resets() {
        let s = PromptHistory.step(PromptHistory.idle(), history, "my draft", -1);
        const r = PromptHistory.step(s, history, "third", 1);
        verify(r.handled);
        compare(r.text, "my draft");
        compare(r.index, -1);
        compare(r.backup, "");
    }

    function test_round_trip_up_up_down_down() {
        let s = PromptHistory.step(PromptHistory.idle(), history, "wip", -1);
        s = PromptHistory.step(s, history, "third", -1);
        s = PromptHistory.step(s, history, "second", 1);
        compare(s.text, "third");
        s = PromptHistory.step(s, history, "third", 1);
        compare(s.text, "wip");
        compare(s.index, -1);
    }
}
