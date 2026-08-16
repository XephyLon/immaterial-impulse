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
}
