import QtTest
import "../modules/common/functions/parallax.js" as Parallax

// The wallpaper parallax maths, kept out of Background.qml so it can be tested
// without a compositor. Background.qml only feeds live state in and applies the
// pixel offsets it gets back - every decision about WHERE the wallpaper sits is
// made here.
//
// The effect is one pan across an overscanned wallpaper: the picture is drawn
// larger than the screen, and these fractions choose which part of the overflow
// is on screen. 0 is the left/top edge of the picture, 1 the right/bottom, 0.5
// centred (which is also the neutral position when nothing is driving an axis).
TestCase {
    name: "ParallaxTest"

    function baseState(overrides) {
        const state = {
            workspaceIndex: 0,
            totalWorkspaces: 10,
            vertical: false,
            enableWorkspace: true,
            enableSidebar: true,
            sidebarLeftOpen: false,
            sidebarRightOpen: false,
            sidebarFraction: 0.05,
            overflowX: 500,
            overflowY: 200
        };
        for (const key in overrides)
            state[key] = overrides[key];
        return state;
    }

    // --- Workspace parallax ------------------------------------------------

    function test_first_workspace_sits_at_the_start_of_the_picture() {
        compare(Parallax.fractions(baseState({workspaceIndex: 0})).x, 0);
    }

    function test_last_workspace_sits_at_the_end_of_the_picture() {
        compare(Parallax.fractions(baseState({workspaceIndex: 9})).x, 1);
    }

    function test_middle_workspace_is_proportional() {
        // 5 of 10 workspaces -> 5/9 of the way across, not 0.5: the pan runs
        // between workspace centres, so the last workspace can reach the edge.
        const f = Parallax.fractions(baseState({workspaceIndex: 5})).x;
        fuzzyCompare(f, 5 / 9, 0.0001);
    }

    function test_a_single_workspace_stays_centred() {
        // Nothing to pan across; dividing by (total - 1) would be a divide by
        // zero and put the wallpaper at NaN, which renders as nothing at all.
        compare(Parallax.fractions(baseState({totalWorkspaces: 1})).x, 0.5);
    }

    function test_workspace_parallax_off_leaves_the_axis_centred() {
        const f = Parallax.fractions(baseState({workspaceIndex: 9, enableWorkspace: false}));
        compare(f.x, 0.5);
    }

    function test_workspace_index_beyond_the_count_is_clamped() {
        // Hyprland IDs can exceed the shown chunk (workspace 12 of 10 shown).
        compare(Parallax.fractions(baseState({workspaceIndex: 30})).x, 1);
    }

    function test_negative_workspace_index_is_clamped() {
        compare(Parallax.fractions(baseState({workspaceIndex: -3})).x, 0);
    }

    // --- Sidebar parallax --------------------------------------------------

    function test_right_sidebar_pushes_the_view_right() {
        const closed = Parallax.fractions(baseState({workspaceIndex: 4})).x;
        const open = Parallax.fractions(baseState({workspaceIndex: 4, sidebarRightOpen: true})).x;
        verify(open > closed);
        fuzzyCompare(open - closed, 0.05, 0.0001);
    }

    function test_left_sidebar_pushes_the_view_left() {
        const closed = Parallax.fractions(baseState({workspaceIndex: 4})).x;
        const open = Parallax.fractions(baseState({workspaceIndex: 4, sidebarLeftOpen: true})).x;
        verify(open < closed);
        fuzzyCompare(closed - open, 0.05, 0.0001);
    }

    function test_both_sidebars_open_cancel_out() {
        const neither = Parallax.fractions(baseState({workspaceIndex: 4})).x;
        const both = Parallax.fractions(baseState({
            workspaceIndex: 4, sidebarLeftOpen: true, sidebarRightOpen: true})).x;
        fuzzyCompare(both, neither, 0.0001);
    }

    function test_sidebar_nudge_alone_moves_a_centred_wallpaper() {
        // With workspace parallax off, the sidebars are still a reason to move:
        // this is what makes the effect visible to someone using one workspace.
        const f = Parallax.fractions(baseState({
            enableWorkspace: false, sidebarRightOpen: true})).x;
        fuzzyCompare(f, 0.55, 0.0001);
    }

    function test_sidebar_parallax_off_ignores_open_sidebars() {
        const f = Parallax.fractions(baseState({
            workspaceIndex: 4, enableSidebar: false, sidebarRightOpen: true})).x;
        fuzzyCompare(f, Parallax.fractions(baseState({workspaceIndex: 4})).x, 0.0001);
    }

    function test_sidebar_nudge_cannot_push_past_the_edge() {
        // At the last workspace the view is already at the far edge; a further
        // nudge must clamp rather than expose the void beyond the picture.
        const f = Parallax.fractions(baseState({
            workspaceIndex: 9, sidebarRightOpen: true})).x;
        compare(f, 1);
    }

    // --- Vertical parallax -------------------------------------------------

    function test_vertical_mode_moves_the_workspace_pan_to_the_y_axis() {
        const f = Parallax.fractions(baseState({workspaceIndex: 9, vertical: true}));
        compare(f.y, 1);
        // X stops tracking workspaces, but sidebars still live on X - they are
        // horizontal surfaces whichever way the workspaces pan.
        compare(f.x, 0.5);
    }

    function test_vertical_mode_still_honours_the_sidebars_horizontally() {
        const f = Parallax.fractions(baseState({
            workspaceIndex: 9, vertical: true, sidebarRightOpen: true}));
        fuzzyCompare(f.x, 0.55, 0.0001);
        compare(f.y, 1);
    }

    function test_horizontal_mode_leaves_y_centred() {
        compare(Parallax.fractions(baseState({workspaceIndex: 9})).y, 0.5);
    }

    // --- Pixel offsets -----------------------------------------------------

    function test_offsets_are_negative_because_the_picture_slides_left() {
        // The container is larger than the screen and slides under it, so a
        // fraction of 1 means "shifted fully left/up", i.e. negative.
        const o = Parallax.offsets(baseState({workspaceIndex: 9}));
        compare(o.x, -500);
        compare(o.y, -100); // y centred: half of 200
    }

    function test_no_overflow_means_no_movement() {
        // zoom 1.0 leaves nothing to pan across. Every fraction must still map
        // to 0 rather than NaN, or the wallpaper vanishes on a default config.
        const o = Parallax.offsets(baseState({workspaceIndex: 9, overflowX: 0, overflowY: 0}));
        compare(o.x, 0);
        compare(o.y, 0);
    }

    function test_widget_offset_scales_the_wallpaper_offset() {
        // Widgets travel further than the wallpaper (factor > 1), which is what
        // reads as depth rather than as the widgets being glued to the picture.
        compare(Parallax.widgetOffset(-500, 1.2), -600);
        compare(Parallax.widgetOffset(-500, 0), 0);
    }

    function test_widget_offset_is_zero_when_the_wallpaper_has_not_moved() {
        compare(Parallax.widgetOffset(0, 1.2), 0);
    }

    // --- Guards ------------------------------------------------------------

    function test_missing_state_does_not_produce_nan() {
        // Config reads can arrive undefined during startup, before Config.ready.
        // A NaN here propagates into x/y and the wallpaper disappears, so every
        // field falls back rather than trusting the caller.
        const f = Parallax.fractions({});
        verify(!isNaN(f.x));
        verify(!isNaN(f.y));
        const o = Parallax.offsets({});
        compare(o.x, 0);
        compare(o.y, 0);
    }

    // The widget canvas is screen-sized, so the wallpaper's edge-relative
    // offsets mean something different there: half the zoom overflow of static
    // shift, which pushes the canvas off the screen and makes that strip of
    // desktop unreachable. Worst on the axis that never travels - with
    // vertical: false, y parks at CENTRE and the bottom of the screen is lost
    // permanently to motion that does not happen.
    function test_widgetOffsetsRestAtZeroOnAParkedAxis() {
        const state = {
            vertical: false, enableWorkspace: true, enableSidebar: false,
            workspaceIndex: 1, totalWorkspaces: 5,
            overflowX: 358, overflowY: 100.8
        };
        const widget = Parallax.widgetOffsets(state, 1.2);
        compare(widget.y, 0,
                "a parked axis must not shift the canvas at all");
        verify(widget.x !== 0, "the travelling axis must still travel");
    }

    function test_widgetOffsetsAreSymmetricAboutTheCentre() {
        const base = {
            vertical: false, enableWorkspace: true, enableSidebar: false,
            totalWorkspaces: 5, overflowX: 358, overflowY: 100.8
        };
        const first = Parallax.widgetOffsets(
            Object.assign({}, base, { workspaceIndex: 0 }), 1.2);
        const last = Parallax.widgetOffsets(
            Object.assign({}, base, { workspaceIndex: 4 }), 1.2);
        const middle = Parallax.widgetOffsets(
            Object.assign({}, base, { workspaceIndex: 2 }), 1.2);
        compare(middle.x, 0, "the middle workspace is the resting position");
        fuzzyCompare(first.x, -last.x, 0.001,
                     "the swing must be even either side, or one edge loses more "
                     + "desktop than the other");
    }

    // The wallpaper container is genuinely larger than the screen and *wants*
    // its middle shown, so its own offsets keep the CENTRE parking.
    function test_wallpaperOffsetsStillParkAtCentre() {
        const state = {
            vertical: false, enableWorkspace: true, enableSidebar: false,
            workspaceIndex: 1, totalWorkspaces: 5,
            overflowX: 358, overflowY: 100.8
        };
        compare(Parallax.offsets(state).y, -50.4,
                "the wallpaper must still be centred on its parked axis");
    }
}
