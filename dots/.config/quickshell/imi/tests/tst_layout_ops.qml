import QtTest
import "../modules/common/functions/layout_ops.js" as LayoutOps

// What a drag does to the list underneath it. The module was extracted because
// the four surfaces that reorder by dragging did not agree on that, so most of
// what is worth asserting here is the disagreement itself: a swap and a move
// are the same answer for a step of one and different answers for everything
// else, and every check below that could pass under either spelling says so.
TestCase {
    name: "LayoutOpsTest"

    readonly property var five: ["a", "b", "c", "d", "e"]

    function test_a_drag_across_three_neighbours_shifts_them_along() {
        // The whole point of the module. Item 5 ("e") is dropped at position 2,
        // so "b", "c" and "d" each move one place later and keep their order.
        compare(LayoutOps.move(five, 4, 1).join(","), "a,e,b,c,d");
        // Exchanging the two entries is what three of the four call sites did,
        // and it is a different list: "b" is flung to the far end of the run it
        // was standing in. Named here so this check cannot be satisfied by
        // restoring a swap.
        verify(LayoutOps.move(five, 4, 1).join(",") !== "a,e,c,d,b");
    }

    function test_the_same_reorder_read_the_other_way() {
        // Forwards, so the shift runs the other direction: "b" is dropped at
        // position 4 and "c", "d" close up behind it.
        compare(LayoutOps.move(five, 1, 3).join(","), "a,c,d,b,e");
        compare(LayoutOps.move(five, 0, 4).join(","), "b,c,d,e,a");
    }

    function test_a_step_of_one_is_where_the_two_spellings_agree() {
        // The degenerate case, and the reason the bug was invisible on a slow
        // drag: an adjacent move and an adjacent swap produce the same list, so
        // dragging one slot at a time looked correct under both.
        compare(LayoutOps.move(five, 2, 3).join(","), "a,b,d,c,e");
        compare(LayoutOps.move(five, 3, 2).join(","), "a,b,d,c,e");
    }

    function test_an_index_off_the_end_leaves_the_list_alone() {
        // Reachable without anything being wrong: the indices come off live
        // Repeater items and a list that can reflow mid-gesture. The failure to
        // avoid is a hole, so the length is asserted as well as the contents.
        const cases = [[-1, 2], [2, -1], [5, 0], [0, 5], [0, 0]];
        for (const pair of cases) {
            const result = LayoutOps.move(five, pair[0], pair[1]);
            compare(result.join(","), "a,b,c,d,e", "move(" + pair + ") changed the list");
            compare(result.length, 5);
        }
    }

    function test_move_copies_and_moveInPlace_does_not() {
        // The quick toggles mutate the live Config array on purpose
        // (26b625905), so both spellings exist and must run the one arithmetic.
        const source = ["a", "b", "c", "d", "e"];
        const copy = LayoutOps.move(source, 4, 1);
        compare(source.join(","), "a,b,c,d,e", "move must not touch its argument");
        compare(copy.join(","), "a,e,b,c,d");

        const live = ["a", "b", "c", "d", "e"];
        const returned = LayoutOps.moveInPlace(live, 4, 1);
        compare(live.join(","), "a,e,b,c,d", "moveInPlace must reorder the array it was handed");
        verify(returned === live);
    }

    function test_the_nearest_slot_along_a_column_is_found_on_the_axis_that_moves() {
        // A vertical dock: every slot centre has the same x. Comparing that
        // coordinate is not a subtly wrong reorder, it is an inert one - every
        // distance is identical and the answer is whichever slot the loop
        // reached first, whatever the pointer does.
        const column = [
            Qt.point(40, 100),
            Qt.point(40, 200),
            Qt.point(40, 300)
        ];
        const pointer = Qt.point(44, 290);
        compare(LayoutOps.indexAt(column, pointer, "y"), 2);
        compare(LayoutOps.indexAt(column, pointer, "x"), 0,
                "comparing the axis a column does not run along answers the same for every slot");

        // And the mirror image, so neither axis is hardcoded.
        const row = [
            Qt.point(100, 40),
            Qt.point(200, 40),
            Qt.point(300, 40)
        ];
        compare(LayoutOps.indexAt(row, Qt.point(110, 400), "x"), 0);
        compare(LayoutOps.indexAt(row, Qt.point(190, 400), "x"), 1);
    }

    function test_a_two_dimensional_nearest_is_a_real_distance() {
        // The bar's chip editor wraps in a Flow, so its rows are as real as its
        // columns and neither coordinate can be dropped.
        const chips = [
            Qt.point(10, 10),
            Qt.point(90, 10),
            Qt.point(10, 90)
        ];
        compare(LayoutOps.indexAt(chips, Qt.point(20, 80), null), 2);
        compare(LayoutOps.indexAt(chips, Qt.point(80, 20), null), 1);
    }

    function test_a_hole_is_skipped_rather_than_treated_as_the_origin() {
        // Two callers need this: a Repeater item that does not exist yet, and
        // the dragged slot itself, which must never be its own nearest.
        const centres = [Qt.point(10, 10), null, Qt.point(30, 30)];
        compare(LayoutOps.indexAt(centres, Qt.point(11, 11), null), 0);
        compare(LayoutOps.indexAt(centres, Qt.point(20, 21), null), 2,
                "the hole is nearest by position and must not be chosen");
        compare(LayoutOps.indexAt([null, null], Qt.point(0, 0), null), -1);
        compare(LayoutOps.indexAt([], Qt.point(0, 0), "x"), -1);
    }

    function test_a_tie_goes_to_the_lower_index() {
        // Matches every loop this replaced, all of which tested `dist < min`.
        const centres = [Qt.point(0, 0), Qt.point(20, 0)];
        compare(LayoutOps.indexAt(centres, Qt.point(10, 0), "x"), 0);
    }

    function test_insert_places_the_item_at_the_index_it_names() {
        compare(LayoutOps.insert(five, "z", 0).join(","), "z,a,b,c,d,e");
        compare(LayoutOps.insert(five, "z", 2).join(","), "a,b,z,c,d,e");
        // Appending is the end of the list, which is one past the last index -
        // so unlike move, `length` is a legal position here.
        compare(LayoutOps.insert(five, "z", 5).join(","), "a,b,c,d,e,z");
        compare(LayoutOps.insert(five, "z", 6).join(","), "a,b,c,d,e");
        compare(LayoutOps.insert(five, "z", -1).join(","), "a,b,c,d,e");
        compare(five.join(","), "a,b,c,d,e", "insert must not touch its argument");
    }

    function test_remove_takes_out_the_index_it_names() {
        compare(LayoutOps.remove(five, 0).join(","), "b,c,d,e");
        compare(LayoutOps.remove(five, 4).join(","), "a,b,c,d");
        compare(LayoutOps.remove(five, 5).join(","), "a,b,c,d,e");
        compare(LayoutOps.remove(five, -1).join(","), "a,b,c,d,e");
        compare(five.join(","), "a,b,c,d,e", "remove must not touch its argument");
    }

    // ---- dropTarget: which bucket, and where in it -------------------------
    //
    // The bar's three layouts are three lists laid out along one axis, so a
    // drop has to answer two questions at once - which list, and where in it -
    // and the second answer is an INSERTION index (0..length), not a nearest
    // slot: the caller splices with it, and "past the last slot" has to be a
    // representable answer or nothing can ever be dropped at the end.

    // A row of two buckets: left holds slots at x 100 and 200, right one at
    // x 500. The middle is empty and anchored at x 350.
    readonly property var rowBuckets: [
        { centres: [Qt.point(100, 40), Qt.point(200, 40)], anchor: null },
        { centres: [], anchor: Qt.point(350, 40) },
        { centres: [Qt.point(500, 40)], anchor: null }
    ]

    function test_a_drop_before_a_slots_centre_inserts_before_it() {
        const target = LayoutOps.dropTarget(rowBuckets, Qt.point(90, 40), "x");
        compare(target.bucket, 0);
        compare(target.index, 0);
    }

    function test_a_drop_past_a_slots_centre_inserts_after_it() {
        const target = LayoutOps.dropTarget(rowBuckets, Qt.point(110, 40), "x");
        compare(target.bucket, 0);
        compare(target.index, 1);
    }

    function test_a_drop_past_the_last_slot_is_an_append() {
        const target = LayoutOps.dropTarget(rowBuckets, Qt.point(560, 40), "x");
        compare(target.bucket, 2);
        compare(target.index, 1, "one past the last slot, so the caller can append");
    }

    function test_an_empty_bucket_answers_through_its_anchor() {
        // The whole reason the anchor exists: an empty middleLayout has no slot
        // centres at all, and without a stand-in it could never win a drop.
        const target = LayoutOps.dropTarget(rowBuckets, Qt.point(355, 40), "x");
        compare(target.bucket, 1);
        compare(target.index, 0);
    }

    function test_a_bucket_whose_every_slot_is_a_hole_counts_as_empty() {
        // Dragging the only widget of a bucket: its own slot is the hole, so
        // the bucket falls back to its anchor rather than disappearing as a
        // drop target.
        const buckets = [
            { centres: [null], anchor: Qt.point(100, 40) },
            { centres: [Qt.point(500, 40)], anchor: null }
        ];
        const target = LayoutOps.dropTarget(buckets, Qt.point(105, 40), "x");
        compare(target.bucket, 0);
        compare(target.index, 0);
    }

    function test_the_drop_compares_along_the_axis_the_buckets_run() {
        // The same arrangement turned into a column, so neither axis is
        // hardcoded - the inert-comparison lesson from the vertical dock.
        const columnBuckets = [
            { centres: [Qt.point(40, 100), Qt.point(40, 200)], anchor: null },
            { centres: [Qt.point(40, 500)], anchor: null }
        ];
        const target = LayoutOps.dropTarget(columnBuckets, Qt.point(40, 210), "y");
        compare(target.bucket, 0);
        compare(target.index, 2);
    }

    function test_no_candidate_at_all_is_no_target() {
        compare(LayoutOps.dropTarget([], Qt.point(0, 0), "x"), null);
        compare(LayoutOps.dropTarget([{ centres: [null], anchor: null }],
                                     Qt.point(0, 0), "x"), null);
    }

    // ---- the visible-to-stored mapping -------------------------------------
    //
    // The bar draws its layouts FILTERED - an empty tray drops sysTray, a
    // disabled plugin drops its widget - so the index a drag reads off the
    // screen is an index into the visible list, while the store holds the whole
    // one. The mapping is arithmetic over a flags array (flags[i] says whether
    // stored entry i is drawn), kept here so a reorder cannot silently eat the
    // hidden entries.

    function test_nth_visible_walks_the_flags() {
        const flags = [true, false, true, true];
        compare(LayoutOps.nthVisible(flags, 0), 0);
        compare(LayoutOps.nthVisible(flags, 1), 2);
        compare(LayoutOps.nthVisible(flags, 2), 3);
        compare(LayoutOps.nthVisible(flags, 3), -1, "past the visible count is no index");
        compare(LayoutOps.nthVisible([], 0), -1);
    }

    function test_a_visible_insertion_lands_between_the_right_stored_entries() {
        const flags = [true, false, true, true];
        compare(LayoutOps.insertionForVisible(flags, 0), 0);
        compare(LayoutOps.insertionForVisible(flags, 1), 2);
        compare(LayoutOps.insertionForVisible(flags, 2), 3);
        // At or past the visible count the insertion is the stored end, so an
        // append stays an append whatever is hidden at the tail.
        compare(LayoutOps.insertionForVisible(flags, 3), 4);
        compare(LayoutOps.insertionForVisible(flags, 9), 4);
    }

    function test_an_insertion_index_becomes_a_move_destination() {
        // An insertion index counts the gap; a move destination counts the
        // slot. Taking the dragged item out first is what shifts everything
        // past it one place down.
        compare(LayoutOps.moveTargetForInsertion(0, 2), 1);
        compare(LayoutOps.moveTargetForInsertion(0, 3), 2);
        compare(LayoutOps.moveTargetForInsertion(2, 0), 0);
        compare(LayoutOps.moveTargetForInsertion(1, 1), 1);
        compare(LayoutOps.moveTargetForInsertion(1, 2), 1,
                "the gap just past the dragged slot is where it already is");
    }

    function test_the_mapping_reorders_around_a_hidden_entry() {
        // The end-to-end shape a bar reorder runs: stored [a, hidden, b, c],
        // drag the visible "a" to the gap between "b" and "c". The hidden entry
        // stays where it was and the visible order comes out b, a, c.
        const stored = ["a", "hidden", "b", "c"];
        const flags = [true, false, true, true];
        const fromVisible = 0;
        const insertion = 2;
        const visibleDest = LayoutOps.moveTargetForInsertion(fromVisible, insertion);
        const result = LayoutOps.move(stored,
            LayoutOps.nthVisible(flags, fromVisible),
            LayoutOps.nthVisible(flags, visibleDest));
        compare(result.join(","), "hidden,b,a,c");
    }
}
