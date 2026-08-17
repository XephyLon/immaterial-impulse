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
    }

    function test_a_wide_screen_shrinks_by_the_ceiling_instead() {
        // The same drawer on a 5120px monitor is 8% of the width, and a desktop
        // at 92% is the screen with a border round it rather than an object on
        // it. The ceiling is what keeps the shrink - which IS the mode's signal
        // - legible at that size.
        compare(wide.scale, EditMode.MAX_SCALE);
        verify(wide.scale < (5120 - 400 - 48) / 5120);
    }

    function test_the_desktop_rests_dead_centre_on_both_axes() {
        // The reservation for the drawer is in the SIZE, never in the resting
        // position: a geometry that held the drawer's width back on one side
        // makes the entry asymmetric from its first frame, which reads as the
        // desktop being shoved aside rather than shrinking where it is.
        for (const [screen, geometry] of [[[5120, 1440], wide], [[1600, 1000], narrow]]) {
            fuzzyCompare(geometry.x, (screen[0] - geometry.width) / 2, 1e-9);
            fuzzyCompare(geometry.y, (screen[1] - geometry.height) / 2, 1e-9);
            fuzzyCompare(geometry.height / geometry.width, screen[1] / screen[0], 1e-9);
        }
    }

    function test_a_centred_desktop_still_leaves_the_drawer_room_to_open_into() {
        // What the reservation buys, now that it is spent later rather than
        // held back: each side has at least half a drawer plus a margin free,
        // so opening a drawer of `drawerWidth + margin` on the right needs the
        // desktop to travel at most half a drawer left and still leaves a
        // margin behind it. Asserted in both regimes, because on a wide screen
        // it is the ceiling rather than the drawer that decides the scale.
        for (const [screen, geometry] of [[5120, wide], [1600, narrow]]) {
            const free = (screen - geometry.width) / 2;
            verify(free >= 400 / 2 + 24 - 0.5);
            // What stage 5 will have to move the desktop by, and what is left
            // on the other side of it once it has.
            const travel = Math.max(0, (400 + 24) - free);
            verify(free - travel >= 24 - 0.5);
        }
    }

    function test_a_short_screen_is_bound_by_its_height_instead() {
        // On a wide, short panel the vertical margins bind first, so the
        // horizontal slack grows - and it grows on both sides, because the
        // desktop is centred. A geometry that took only the horizontal ratio
        // would put the desktop's top and bottom edges off the screen.
        const panel = EditMode.viewportGeometry({
            screenWidth: 1280, screenHeight: 400, drawerWidth: 120, margin: 40
        });
        fuzzyCompare(panel.scale, (400 - 80) / 400, 1e-9);
        verify(panel.scale < (1280 - 120 - 80) / 1280);
        verify(panel.height <= 400 - 80 + 0.5);
        verify(panel.width <= 1280 - 120 - 80 + 0.5);
        fuzzyCompare(panel.y, 40, 0.5);
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

    function test_the_shrink_is_concentric_on_every_frame_and_not_only_at_rest() {
        // The correction this exists for: a geometry that reserved the drawer's
        // width on one side made the entry a slide as well as a shrink, and it
        // was symmetric nowhere - including at rest. The margins are equal in
        // pairs at every progress because the offset is linear in the scale and
        // takes the same `t`, so this fails on any transform that centres only
        // at the end.
        for (const t of [0, 0.15, 0.5, 0.83, 1]) {
            const at = EditMode.atProgress(wide, t);
            const card = EditMode.cardRect(wide, t, 5120, 1440);
            fuzzyCompare(card.x, 5120 - (card.x + card.width), 1e-6);
            fuzzyCompare(card.y, 1440 - (card.y + card.height), 1e-6);
            fuzzyCompare(at.scale, card.width / 5120, 1e-9);
        }
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

    // ---- the bar and the dock keep their edges ---------------------------
    //
    // The two panels stay where they are at full size (spec §12 stage 8 is
    // editing them in place, and this is not it), so the mode's whole geometry
    // happens inside what is left of the screen. Stage 4 shipped without this
    // and put the toolbar over the bar's widgets and the tab bar over the
    // dock's; every case below is a way that comes back.

    // The numbers this machine's compositor reports for its own two panels
    // (`hyprctl layers`: quickshell:bar at y=5 h=63, quickshell:dock 75 tall),
    // and deliberately UNEQUAL - a top and a bottom inset that match are
    // indistinguishable from a symmetric margin, and every "which edge did you
    // subtract" bug passes on them.
    readonly property real barInset: 68
    readonly property real dockInset: 75
    readonly property real chrome: 56

    readonly property var framed: EditMode.viewportGeometry({
        screenWidth: 5120, screenHeight: 1440, drawerWidth: 400, margin: 24,
        chromeThickness: chrome, insetTop: barInset, insetBottom: dockInset
    })

    function test_the_usable_area_is_the_screen_minus_what_the_panels_occupy() {
        const area = EditMode.usableArea({
            screenWidth: 5120, screenHeight: 1440,
            insetTop: barInset, insetBottom: dockInset, insetLeft: 12, insetRight: 30
        });
        compare(area.x, 12);
        compare(area.y, barInset);
        compare(area.width, 5120 - 12 - 30);
        compare(area.height, 1440 - barInset - dockInset);
        // Absent insets are zero, which is the geometry the mode had before it
        // knew about either panel - not an error and not a default guess.
        const bare = EditMode.usableArea({ screenWidth: 800, screenHeight: 600 });
        compare(bare.x, 0);
        compare(bare.y, 0);
        compare(bare.width, 800);
        compare(bare.height, 600);
    }

    function test_the_desktop_leaves_the_chrome_a_band_of_its_own() {
        // The band above and below the card is a margin, the toolbar, and
        // another margin - so the toolbar centred in it has a whole margin at
        // each end BY CONSTRUCTION rather than by whatever the ceiling left
        // over. That is the correction: the old band was 100.8px at this screen
        // size and the toolbar is 56 centred in it, which starts 22.4px into a
        // screen whose bar occupies the first 68.
        const bandTop = framed.y - barInset;
        const bandBottom = (1440 - dockInset) - (framed.y + framed.height);
        fuzzyCompare(bandTop, 24 + chrome + 24, 0.5);
        fuzzyCompare(bandBottom, 24 + chrome + 24, 0.5);
        // ...and the vertical constraint is what decides the scale here, which
        // is what makes the two numbers above a promise rather than a
        // coincidence of the ceiling.
        verify(framed.scale < EditMode.MAX_SCALE);
    }

    function test_the_desktop_rests_dead_centre_of_the_usable_area() {
        // Centre of what is LEFT, not of the panel: the margins are equal in
        // pairs against the area's edges, and the card is strictly inside the
        // two panels' bands. A geometry that centred on the screen would put
        // the card 3.5px lower here and its chrome on the bar, which is the
        // failure this replaces - so the check is the containment as well as
        // the symmetry.
        const area = framed.area;
        fuzzyCompare(framed.x - area.x,
            (area.x + area.width) - (framed.x + framed.width), 1e-6);
        fuzzyCompare(framed.y - area.y,
            (area.y + area.height) - (framed.y + framed.height), 1e-6);
        verify(framed.y >= barInset);
        verify(framed.y + framed.height <= 1440 - dockInset);
    }

    function test_a_panel_on_a_side_edge_takes_from_the_horizontal_room_too() {
        // The bar is vertical on this setting and the dock has four edges, so
        // the left and right insets are not decoration. Measured where the
        // horizontal constraint binds, or the ceiling answers for both.
        const sided = EditMode.viewportGeometry({
            screenWidth: 1600, screenHeight: 1000, drawerWidth: 400, margin: 24,
            insetLeft: 60, insetRight: 40
        });
        fuzzyCompare(sided.width, 1600 - 60 - 40 - 400 - 48, 0.5);
        verify(sided.x >= 60);
        verify(sided.x + sided.width <= 1600 - 40);
    }

    function test_no_insets_and_no_chrome_is_the_geometry_the_mode_had_before() {
        // The regression pin for every case above this section: adding the two
        // terms must not have moved the answer for a caller that passes
        // neither. If this ever needs updating, the mode's geometry changed for
        // a screen with no bar and no dock, which nothing here intends.
        const plain = EditMode.viewportGeometry({
            screenWidth: 5120, screenHeight: 1440, drawerWidth: 400, margin: 24
        });
        compare(plain.scale, wide.scale);
        compare(plain.x, wide.x);
        compare(plain.y, wide.y);
        compare(plain.area.x, 0);
        compare(plain.area.y, 0);
        compare(plain.area.width, 5120);
        compare(plain.area.height, 1440);
    }

    function test_the_chromes_band_closes_in_as_the_desktop_shrinks() {
        // The chrome is placed between `areaRect` and `cardRect`, and at
        // progress 0 the two coincide - so both bands have zero height and both
        // pieces are parked half off screen, arriving WITH the desktop rather
        // than sliding in from wherever the bar happens to end. A band fixed at
        // the usable area would put the toolbar just under the bar from the
        // first frame of the entry.
        const start = EditMode.areaRect(framed, 0, 5120, 1440);
        compare(start.x, 0);
        compare(start.y, 0);
        compare(start.width, 5120);
        compare(start.height, 1440);

        const end = EditMode.areaRect(framed, 1, 5120, 1440);
        fuzzyCompare(end.y, barInset, 1e-9);
        fuzzyCompare(end.height, 1440 - barInset - dockInset, 1e-9);

        const half = EditMode.areaRect(framed, 0.5, 5120, 1440);
        fuzzyCompare(half.y, barInset / 2, 1e-9);
        fuzzyCompare(half.height, (1440 + (1440 - barInset - dockInset)) / 2, 1e-9);

        // And the band it opens is never negative once the mode has arrived,
        // at any progress: the card is inside the area for every t, because
        // both rectangles are linear in t and the containment holds at both
        // ends.
        for (const t of [0.2, 0.5, 0.9, 1]) {
            const card = EditMode.cardRect(framed, t, 5120, 1440);
            const area = EditMode.areaRect(framed, t, 5120, 1440);
            verify(card.y >= area.y - 1e-6);
            verify(card.y + card.height <= area.y + area.height + 1e-6);
        }
    }
}
