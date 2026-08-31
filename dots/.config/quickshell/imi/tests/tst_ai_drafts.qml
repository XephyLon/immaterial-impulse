import QtTest
import "../services/ai/ai_drafts.js" as Drafts

TestCase {
    name: "AiDraftsTest"

    function test_set_read_clear() {
        let map = Drafts.withDraft({}, "abc", "half a thought");
        compare(Drafts.draftFor(map, "abc"), "half a thought");
        compare(Drafts.draftFor(map, "other"), "");
        map = Drafts.withDraft(map, "abc", "");
        verify(!("abc" in map), "empty text deletes the slot");
    }

    function test_new_chat_slot() {
        let map = Drafts.withDraft({}, "", "unminted");
        compare(Drafts.draftFor(map, ""), "unminted");
        const pruned = Drafts.prune(map, ["x", "y"]);
        compare(Drafts.draftFor(pruned, ""), "unminted", "the new-chat slot survives pruning");
    }

    function test_prune_drops_dead_sessions() {
        let map = Drafts.withDraft({}, "dead", "gone soon");
        map = Drafts.withDraft(map, "alive", "stays");
        const pruned = Drafts.prune(map, ["alive"]);
        verify(!("dead" in pruned));
        compare(Drafts.draftFor(pruned, "alive"), "stays");
    }
}
