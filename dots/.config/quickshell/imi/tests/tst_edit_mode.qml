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
    // A 16:10 laptop panel, where 400px of drawer is a quarter of the width and
    // the derivation is the tighter of the two constraints.
    readonly property var narrow: EditMode.viewportGeometry({
        screenWidth: 1600, screenHeight: 1000, drawerWidth: 400, margin: 24
    })

    function test_the_desktop_shrinks_by_exactly_what_the_drawer_will_need() {
        // 1600 - 400 - 2*24 = 1152 of room, so the scale is the ratio of that
        // to the screen and the drawn width is that room exactly. Asserted as
        // the width rather than only as the scale: the scale is the mechanism,
        // the width is the promise.
        fuzzyCompare(narrow.width, 1152, 0.5);
        fuzzyCompare(narrow.scale, 1152 / 1600, 1e-9);
        // The space left over on the right is the drawer plus its gap.
        fuzzyCompare(1600 - (narrow.x + narrow.width), 400 + 24, 0.5);
    }

    function test_a_wide_screen_shrinks_by_the_ceiling_instead() {
        // The same drawer on a 5120px monitor is 8% of the width, and a desktop
        // at 92% is the screen with a border round it rather than an object on
        // it. The ceiling is what keeps the shrink - which IS the mode's signal
        // - legible at that size.
        compare(wide.scale, EditMode.MAX_SCALE);
        verify(wide.scale < (5120 - 400 - 48) / 5120);
    }

    function test_the_ceiling_can_only_give_the_drawer_more_room_than_it_asked_for() {
        // The invariant the derivation exists for, asserted across both
        // regimes: whatever decides the scale, the slot to the right of the
        // desktop still holds the drawer plus its gap. A ceiling that shrank the
        // desktop by moving its left edge, or that capped the scale without
        // re-centring, would break this while looking fine on one screen.
        for (const [width, geometry] of [[5120, wide], [1600, narrow]]) {
            verify(width - (geometry.x + geometry.width) >= 400 + 24 - 0.5);
            fuzzyCompare(geometry.x, 24, 1e-9);
        }
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
            screenWidth: 1600, screenHeight: 1000, drawerWidth: 400, margin: 24
        });
        compare(closed.width, narrow.width);
        compare(closed.x, narrow.x);
        // Measured where the drawer is what decides the scale, so a caller that
        // started passing 0 while the drawer was shut has to change this number.
        // On a screen wide enough for the ceiling to bind, both answers are the
        // ceiling and the check would be vacuous.
        verify(EditMode.viewportGeometry({
            screenWidth: 1600, screenHeight: 1000, drawerWidth: 0, margin: 24
        }).width !== narrow.width);
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

    function test_the_card_is_the_whole_screen_until_the_mode_starts() {
        // What "the chrome stands down completely on exit" rests on: at rest the
        // rectangle the corner, the border and the shadow are drawn around is
        // the screen itself, so there is nothing inset to leave behind.
        const rest = EditMode.cardRect(wide, 0, 5120, 1440);
        compare(rest.x, 0);
        compare(rest.y, 0);
        compare(rest.width, 5120);
        compare(rest.height, 1440);
    }

    function test_the_card_is_the_desktop_and_not_a_second_derivation_of_it() {
        // The chrome frames the transform's own answer. Checked against
        // atProgress at three points rather than against the geometry, because
        // a card computed from `geometry` alone would be right at 1 and wrong
        // for every frame of the entry - which is where a frame off by the
        // scale reads as the border sliding across the desktop.
        for (const t of [0.25, 0.6, 1]) {
            const applied = EditMode.atProgress(wide, t);
            const card = EditMode.cardRect(wide, t, 5120, 1440);
            fuzzyCompare(card.x, applied.x, 1e-9);
            fuzzyCompare(card.y, applied.y, 1e-9);
            fuzzyCompare(card.width, 5120 * applied.scale, 1e-9);
            fuzzyCompare(card.height, 1440 * applied.scale, 1e-9);
        }
        const settled = EditMode.cardRect(wide, 1, 5120, 1440);
        fuzzyCompare(settled.width, wide.width, 1e-9);
        fuzzyCompare(settled.height, wide.height, 1e-9);
    }
}
