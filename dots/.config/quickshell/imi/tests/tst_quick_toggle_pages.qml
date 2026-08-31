import QtTest
import "../modules/common/functions/quick_toggle_pages.js" as Pages

// The quick-toggle PAGES, as arithmetic: migration, one-home-per-toggle,
// add/prune, cross-page moves, and the one signature the panel observes.
// Everything is copy-on-write - the store is a nested list<var>, and an
// inner array mutated in place never notifies the outer property.
TestCase {
    name: "QuickTogglePagesTest"

    function entry(type, size) { return { type: type, size: size ?? 1 }; }

    function test_migration_wraps_the_legacy_flat_list_as_one_page() {
        const pages = Pages.normalise([], [entry("network", 2), entry("mic")]);
        compare(pages.length, 1);
        compare(pages[0].map(e => e.type).join(","), "network,mic");
        compare(pages[0][0].size, 2);
    }

    function test_no_pages_and_no_legacy_is_one_empty_page() {
        compare(Pages.normalise([], []).length, 1);
        compare(Pages.normalise([], [])[0].length, 0);
        compare(Pages.normalise(null, undefined).length, 1);
    }

    function test_stored_pages_win_over_the_legacy_list() {
        const pages = Pages.normalise([[entry("audio")]], [entry("network")]);
        compare(pages.length, 1);
        compare(pages[0][0].type, "audio");
    }

    function test_one_home_per_toggle_first_occurrence_wins() {
        const pages = Pages.normalise(
            [[entry("network"), entry("mic")], [entry("mic"), entry("audio")]], []);
        compare(pages[0].map(e => e.type).join(","), "network,mic");
        compare(pages[1].map(e => e.type).join(","), "audio");
    }

    function test_malformed_entries_and_pages_are_dropped() {
        const pages = Pages.normalise(
            [[entry("network"), null, { size: 2 }], "junk", [entry("mic")]], []);
        compare(pages.length, 2);
        compare(pages[0].map(e => e.type).join(","), "network");
        compare(pages[1][0].type, "mic");
    }

    function test_add_and_prune() {
        const added = Pages.withAddedPage([[entry("network")]]);
        compare(added.length, 2);
        compare(added[1].length, 0);
        const pruned = Pages.pruned([[], [entry("network")], []]);
        compare(pruned.length, 1);
        compare(pruned[0][0].type, "network");
        compare(Pages.pruned([[], []]).length, 1, "never fewer than one page");
    }

    function test_cross_page_move_keeps_both_orders() {
        const pages = [[entry("network"), entry("mic"), entry("audio")], [entry("bluetooth")]];
        const moved = Pages.withMove(pages, 0, 1, 1, 0);
        compare(moved[0].map(e => e.type).join(","), "network,audio");
        compare(moved[1].map(e => e.type).join(","), "mic,bluetooth");
        // ...and the source is untouched (copy-on-write).
        compare(pages[0].length, 3);
    }

    function test_same_page_move_is_layout_ops_move() {
        const moved = Pages.withMove(
            [[entry("a1"), entry("b2"), entry("c3")]], 0, 2, 0, 0);
        compare(moved[0].map(e => e.type).join(","), "c3,a1,b2");
    }

    function test_insert_remove_resize() {
        const pages = [[entry("network")], []];
        const inserted = Pages.withInsert(pages, 1, entry("mic"));
        compare(inserted[1][0].type, "mic");
        const rejected = Pages.withInsert(inserted, 0, entry("mic"));
        compare(rejected[0].length, 1, "a second home is refused");
        const resized = Pages.withResize(inserted, 1, 0, 3);
        compare(resized[1][0].size, 3);
        const removed = Pages.withRemove(inserted, 0, 0);
        compare(removed[0].length, 0);
    }

    function test_used_types_and_clamp() {
        const used = Pages.usedTypes([[entry("network")], [entry("mic")]]);
        verify(used.network && used.mic && !used.audio);
        compare(Pages.clampPage([[], []], 5), 1);
        compare(Pages.clampPage([[], []], -1), 0);
    }

    function test_signature_covers_every_page() {
        const a = Pages.signatureOf([[entry("network")], [entry("mic")]], 5);
        const b = Pages.signatureOf([[entry("network")], [entry("mic", 2)]], 5);
        const c = Pages.signatureOf([[entry("network"), entry("mic")]], 5);
        verify(a !== b, "a size change on page 2 changes the signature");
        verify(a !== c, "the page split itself is part of the signature");
    }
}
