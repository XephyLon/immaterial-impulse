import QtTest
import "../modules/common/plugins/gridResize.js" as GridResize

// The arithmetic behind a resizable widget's span change: how long the move
// takes, when its content swaps, and which changes are moves at all.
//
// The motion itself is unreachable from here - `qmltestrunner` cannot construct
// a `PluginWidget` - so `WidgetResizeMotionRuntimeTest.qml` scores whether the
// width is genuinely in flight. What this pins is the three decisions that can
// be got wrong without any of that being visible: a drag answered on the same
// long curve as a commit, a content swap that lands outside the move it is
// meant to hide inside, and a widget dissolving on login because the store
// answering for the first time looks like a resize.
TestCase {
    name: "GridResizeTest"

    // --- how long ---------------------------------------------------------

    function test_a_previewed_span_gets_the_shorter_curve() {
        compare(GridResize.resizeDurationMs(true, 350, 500), 350);
    }

    function test_a_committed_span_gets_the_full_curve() {
        compare(GridResize.resizeDurationMs(false, 350, 500), 500);
    }

    // Escape clears the preview before the size changes, so the return to the
    // span the drag started from is not a preview and reads as a deliberate
    // move rather than as a snap back.
    function test_the_cancel_is_a_commit_length_move() {
        compare(GridResize.resizeDurationMs(false, 350, 500), 500);
    }

    // --- when the content swaps -------------------------------------------

    function test_the_swap_lands_at_the_midpoint_of_whichever_move_is_running() {
        compare(GridResize.contentSwapHalfMs(500), 250);
        compare(GridResize.contentSwapHalfMs(350), 175);
    }

    function test_two_halves_never_outlast_the_move_they_sit_inside() {
        for (const duration of [0, 1, 150, 200, 350, 351, 500, 650]) {
            verify(2 * GridResize.contentSwapHalfMs(duration) <= duration + 1,
                   "swap outlasts a " + duration + "ms move");
        }
    }

    function test_a_nonsense_duration_is_no_fade_rather_than_a_stuck_one() {
        // A NaN duration on a NumberAnimation runs forever, which would leave
        // the content parked at zero opacity with nothing reporting why.
        compare(GridResize.contentSwapHalfMs(NaN), 0);
        compare(GridResize.contentSwapHalfMs(undefined), 0);
        compare(GridResize.contentSwapHalfMs(-100), 0);
    }

    // --- which changes are moves ------------------------------------------

    function test_a_real_span_change_animates() {
        compare(GridResize.animatesSpanSwap("3x2", "2x2"), true);
        compare(GridResize.animatesSpanSwap("2x1", "3x2"), true);
    }

    function test_the_first_span_the_host_resolves_is_adopted_in_place() {
        // Every widget passes through this once, and a widget whose stored span
        // is not its manifest default passes through it again when
        // plugin-state.json lands.
        compare(GridResize.animatesSpanSwap("", "3x2"), false);
    }

    function test_a_span_that_did_not_change_is_not_a_move() {
        // The grip re-previews on every mouse move, and the nearest span is
        // usually the one already showing.
        compare(GridResize.animatesSpanSwap("2x2", "2x2"), false);
    }

    function test_losing_the_span_is_not_a_move_either() {
        // A content-sized widget formats as "", and so does a manifest whose
        // grid stopped resolving.
        compare(GridResize.animatesSpanSwap("2x2", ""), false);
        compare(GridResize.animatesSpanSwap("2x2", undefined), false);
        compare(GridResize.animatesSpanSwap(null, "2x2"), false);
    }
}
