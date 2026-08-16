import QtTest
import "../modules/common/functions/edit_mode.js" as EditMode

// Edit Mode's two testable decisions: which of four things Escape does, and how
// far the desktop shrinks. Everything else about the mode is a transform on a
// layer surface, which `qmltestrunner` cannot construct at all - so these two
// are where a regression can be caught cheaply, and the runtime harness
// (EditModeRuntimeTest.qml) is where the rest is.
TestCase {
    name: "EditModeTest"

    function test_escape_cancels_a_gesture_before_anything_else() {
        // A drag, a grip resize or a reorder in flight owns the key: the mode
        // stays on and the gesture is put back. Asserted with a selection and a
        // non-default tab also present, because precedence is the whole point
        // of the ladder and each branch alone would pass a `||` chain.
        compare(EditMode.resolveEscape({
            gestureInFlight: true, selectionCount: 3, tab: "lockscreen"
        }), "cancelGesture");
    }

    function test_escape_clears_a_selection_before_changing_tab() {
        compare(EditMode.resolveEscape({
            gestureInFlight: false, selectionCount: 2, tab: "lockscreen"
        }), "clearSelection");
    }

    function test_escape_returns_to_the_desktop_tab_before_leaving() {
        compare(EditMode.resolveEscape({
            gestureInFlight: false, selectionCount: 0, tab: "lockscreen"
        }), "desktopTab");
    }

    function test_escape_leaves_the_mode_only_when_nothing_else_answers() {
        compare(EditMode.resolveEscape({
            gestureInFlight: false, selectionCount: 0, tab: EditMode.DESKTOP_TAB
        }), "exit");
        // An absent tab is the desktop one. The caller does not have a tab bar
        // until stage 4 and must not have to invent a string to get an exit.
        compare(EditMode.resolveEscape({ gestureInFlight: false, selectionCount: 0 }), "exit");
        compare(EditMode.resolveEscape({}), "exit");
    }

    readonly property var wide: EditMode.viewportGeometry({
        screenWidth: 5120, screenHeight: 1440, drawerWidth: 400, margin: 24
    })

    function test_the_desktop_shrinks_by_exactly_what_the_drawer_will_need() {
        // 5120 - 400 - 2*24 = 4672 of room, so the scale is the ratio of that
        // to the screen and the drawn width is that room exactly. Asserted as
        // the width rather than only as the scale: the scale is the mechanism,
        // the width is the promise.
        fuzzyCompare(wide.width, 4672, 0.5);
        fuzzyCompare(wide.scale, 4672 / 5120, 1e-9);
        // The space left over on the right is the drawer plus its gap.
        fuzzyCompare(5120 - (wide.x + wide.width), 400 + 24, 0.5);
    }

    function test_the_desktop_keeps_its_aspect_and_is_centred_vertically() {
        fuzzyCompare(wide.height / wide.width, 1440 / 5120, 1e-9);
        fuzzyCompare(wide.y, (1440 - wide.height) / 2, 0.5);
        fuzzyCompare(wide.x, 24, 1e-9);
    }

    function test_a_short_screen_is_bound_by_its_height_instead() {
        // On a wide, short panel the vertical margins bind first, so the
        // horizontal slack grows - and it grows on the drawer's side, which is
        // where extra room is wanted. A geometry that took only the horizontal
        // ratio would put the desktop's top and bottom edges off the screen.
        const panel = EditMode.viewportGeometry({
            screenWidth: 1280, screenHeight: 400, drawerWidth: 120, margin: 40
        });
        fuzzyCompare(panel.scale, (400 - 80) / 400, 1e-9);
        verify(panel.scale < (1280 - 120 - 80) / 1280);
        verify(panel.height <= 400 - 80 + 0.5);
        verify(panel.width <= 1280 - 120 - 80 + 0.5);
    }

    function test_the_inset_does_not_depend_on_the_drawer_being_open() {
        // There is no open-state input, and there must not be one: opening the
        // drawer translates the desktop, it never resizes it. The check that
        // can see a regression is that the geometry is a function of the
        // drawer's WIDTH alone - so a caller that started passing 0 while the
        // drawer was shut would have to change this number.
        const closed = EditMode.viewportGeometry({
            screenWidth: 5120, screenHeight: 1440, drawerWidth: 400, margin: 24
        });
        compare(closed.width, wide.width);
        compare(closed.x, wide.x);
        verify(EditMode.viewportGeometry({
            screenWidth: 5120, screenHeight: 1440, drawerWidth: 0, margin: 24
        }).width !== wide.width);
    }

    function test_a_screen_too_narrow_for_the_drawer_still_answers_a_usable_scale() {
        // Reachable on a 1024px-wide panel beside a 400px drawer with big
        // margins. The arithmetic's honest answer is a negative scale, which
        // renders as a desktop turned inside out rather than as an error.
        const cramped = EditMode.viewportGeometry({
            screenWidth: 300, screenHeight: 200, drawerWidth: 400, margin: 24
        });
        compare(cramped.scale, EditMode.MIN_SCALE);
        verify(cramped.width > 0);
        // Nothing to divide by either, when a screen has not reported a size.
        const nothing = EditMode.viewportGeometry({
            screenWidth: 0, screenHeight: 0, drawerWidth: 400, margin: 24
        });
        compare(nothing.scale, 1);
    }

    function test_the_transform_interpolates_from_identity() {
        // The entry animation is one scalar, so there is no frame in which the
        // scale has arrived and the offset has not.
        const start = EditMode.atProgress(wide, 0);
        compare(start.scale, 1);
        compare(start.x, 0);
        compare(start.y, 0);

        const end = EditMode.atProgress(wide, 1);
        compare(end.scale, wide.scale);
        compare(end.x, wide.x);
        compare(end.y, wide.y);

        const half = EditMode.atProgress(wide, 0.5);
        fuzzyCompare(half.scale, 1 + (wide.scale - 1) / 2, 1e-9);
        fuzzyCompare(half.x, wide.x / 2, 1e-9);

        // A progress outside [0, 1] is what an interruptible Behavior can hand
        // in on an overshooting curve; it clamps rather than magnifying.
        compare(EditMode.atProgress(wide, 1.4).scale, wide.scale);
        compare(EditMode.atProgress(wide, -0.3).scale, 1);
    }
}
