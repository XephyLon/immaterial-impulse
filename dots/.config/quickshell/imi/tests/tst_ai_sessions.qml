import QtTest
import "../services/ai/ai_sessions.js" as Sessions

// The sessions system's decisions as arithmetic: what a session is called,
// how the list orders, how the folds edit it, and how a legacy flat chat
// file becomes a session. The service above this owns only files and
// debounce.
TestCase {
    name: "AiSessionsTest"

    function meta(id, title, updatedAt, pinned) {
        return { id: id, title: title, createdAt: updatedAt, updatedAt: updatedAt, pinned: pinned ?? false };
    }

    function test_title_from_first_prompt() {
        compare(Sessions.titleFrom("  How do I    tune the bar's margins?  "),
            "How do I tune the bar's margins?");
        const capped = Sessions.titleFrom("x".repeat(80));
        verify(capped.length <= 41, "capped");
        verify(capped.endsWith("…"), "capped titles say so");
        compare(Sessions.titleFrom(""), "");
        compare(Sessions.titleFrom("/model gemini"), "/model gemini",
            "a command prompt is still a title; the caller decides what mints");
    }

    function test_sorted_index_pins_first_then_recency() {
        const rows = Sessions.sortedIndex([
            meta("a", "old", 100), meta("b", "new", 300),
            meta("c", "pinned-old", 50, true), meta("d", "mid", 200)
        ]);
        compare(rows.map(r => r.id).join(","), "c,b,d,a");
    }

    function test_ago_label_speaks_human() {
        const now = 1000000000000;
        compare(Sessions.agoLabel(now, now - 30 * 1000), "now");
        compare(Sessions.agoLabel(now, now - 5 * 60 * 1000), "5m");
        compare(Sessions.agoLabel(now, now - 3 * 3600 * 1000), "3h");
        compare(Sessions.agoLabel(now, now - 2 * 86400 * 1000), "2d");
    }

    function test_legacy_file_becomes_a_session() {
        const messages = [
            { role: "user", rawContent: "Explain the dock's magnify curve" },
            { role: "assistant", rawContent: "It is a gaussian..." }
        ];
        const session = Sessions.legacyToSession(messages, "id123", 42);
        compare(session.meta.id, "id123");
        compare(session.meta.title, "Explain the dock's magnify curve");
        compare(session.meta.createdAt, 42);
        compare(session.meta.pinned, false);
        compare(session.messages.length, 2);
        // No user message: falls back rather than titling from the answer.
        const odd = Sessions.legacyToSession([{ role: "assistant", rawContent: "hello" }], "x", 1);
        compare(odd.meta.title, "");
    }

    function test_folds_edit_the_index() {
        const rows = [meta("a", "one", 100), meta("b", "two", 200)];
        const renamed = Sessions.applyRename(rows, "a", "won");
        compare(renamed.find(r => r.id === "a").title, "won");
        compare(rows.find(r => r.id === "a").title, "one", "copy, not mutation");
        const pinned = Sessions.applyPin(renamed, "a", true);
        compare(Sessions.sortedIndex(pinned)[0].id, "a");
        const removed = Sessions.applyRemove(pinned, "b");
        compare(removed.length, 1);
        const touched = Sessions.applyTouch(rows, "a", "retitled", 999);
        compare(touched.find(r => r.id === "a").updatedAt, 999);
        compare(touched.find(r => r.id === "a").title, "retitled");
        const grown = Sessions.applyTouch(rows, "new-id", "fresh", 500);
        compare(grown.length, 3, "an unknown id is an insert");
    }

    function test_model_titles_are_stripped_of_their_decorations() {
        compare(Sessions.titleFromModelReply('"Wallpaper Engine Crash"', "fb"), "Wallpaper Engine Crash");
        compare(Sessions.titleFromModelReply("Title: Fixing the follow scroll.", "fb"), "Fixing the follow scroll");
        compare(Sessions.titleFromModelReply("**Currency Widget Ideas**\nplus rambling", "fb"), "Currency Widget Ideas");
        compare(Sessions.titleFromModelReply("   \n\n", "the fallback"), "the fallback", "empty keeps the fallback");
        const capped = Sessions.titleFromModelReply("x".repeat(200), "fb");
        verify(capped.length <= 61, "capped like every other title");
    }

    function test_rebuild_folds_meta_lines() {
        const lines = [
            JSON.stringify(meta("a", "one", 100)),
            "not json at all",
            JSON.stringify(meta("b", "two", 200))
        ];
        const rows = Sessions.rebuildIndex(lines);
        compare(rows.length, 2, "a corrupt meta is dropped, not fatal");
        compare(rows[0].id, "b", "rebuilt sorted");
    }
}
