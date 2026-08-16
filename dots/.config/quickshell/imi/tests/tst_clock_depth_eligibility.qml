import QtTest
import "../modules/common/functions/clockDepth.js" as ClockDepth

// When the depth layer may show the wallpaper's subject over the desktop
// widgets, and where its mask has to land to line up with the picture.
//
// The refusals are the interesting half. Each one is a wallpaper the shell does
// not own the pixels of, has no file to segment, or is in the middle of
// replacing - and each of them fails silently on screen if it is wrong: a
// silhouette over a video, a stale cutout mid-switch, a mask from one image
// pasted over another.
TestCase {
    name: "ClockDepthTest"

    function showing(overrides) {
        // A wallpaper that qualifies in every respect, so each case below turns
        // exactly one thing off and nothing else can be doing the work.
        const state = {
            enable: true,
            maskPath: "/cache/clock-depth/abc.png",
            optedOut: false,
            weActive: false,
            wallpaperIsVideo: false,
            centeredWallpaper: false,
            screenLocked: false,
            transitionInFlight: false
        };
        for (const key in overrides)
            state[key] = overrides[key];
        return ClockDepth.eligible(state);
    }

    function test_a_still_wallpaper_with_an_accepted_mask_shows() {
        compare(showing({}), true);
    }

    function test_the_global_switch_refuses() {
        compare(showing({ enable: false }), false);
    }

    function test_a_wallpaper_with_no_mask_refuses() {
        compare(showing({ maskPath: "" }), false);
    }

    function test_an_undefined_mask_path_refuses_rather_than_throwing() {
        compare(showing({ maskPath: undefined }), false);
    }

    function test_an_opt_out_beats_a_mask_that_is_still_on_disk() {
        // The decline marker and the mask are files beside each other, and a
        // mask left there must not outvote the user's last word.
        compare(showing({ optedOut: true }), false);
    }

    function test_a_live_wallpaper_engine_project_refuses() {
        compare(showing({ weActive: true }), false);
    }

    function test_a_video_wallpaper_refuses() {
        compare(showing({ wallpaperIsVideo: true }), false);
    }

    function test_centred_wallpaper_mode_refuses() {
        compare(showing({ centeredWallpaper: true }), false);
    }

    function test_the_lock_screen_refuses() {
        compare(showing({ screenLocked: true }), false);
    }

    function test_a_switch_in_flight_refuses() {
        compare(showing({ transitionInFlight: true }), false);
    }

    function test_an_empty_state_refuses_rather_than_throwing() {
        compare(ClockDepth.eligible({}), false);
        compare(ClockDepth.eligible(undefined), false);
    }

    // coverRect: where the mask goes so it masks the pixels it was cut from.

    function test_a_wider_source_than_the_box_overflows_horizontally() {
        // 2:1 source into a 1:1 box. Height is the binding axis, so the picture
        // is twice as wide as the box and hangs half a box off each side.
        const r = ClockDepth.coverRect(2000, 1000, 500, 500);
        compare(r.width, 1000);
        compare(r.height, 500);
        compare(r.x, -250);
        compare(r.y, 0);
    }

    function test_a_taller_source_than_the_box_overflows_vertically() {
        const r = ClockDepth.coverRect(1000, 2000, 500, 500);
        compare(r.width, 500);
        compare(r.height, 1000);
        compare(r.x, 0);
        compare(r.y, -250);
    }

    function test_a_matching_aspect_fills_the_box_exactly() {
        const r = ClockDepth.coverRect(3840, 1080, 5120, 1440);
        compare(r.x, 0);
        compare(r.y, 0);
        compare(r.width, 5120);
        compare(r.height, 1440);
    }

    function test_the_rect_covers_the_box_on_both_axes() {
        // The invariant that matters: whatever the aspects, no part of the box
        // is left unmasked. A rect that fell short would leave a band of
        // wallpaper drawn at full opacity over the widgets.
        const cases = [[3840, 1594], [7680, 2160], [1080, 1920], [1024, 1024], [8400, 4725]];
        for (let i = 0; i < cases.length; i++) {
            const r = ClockDepth.coverRect(cases[i][0], cases[i][1], 5632, 1584);
            verify(r.x <= 0.001, "left edge uncovered for " + cases[i]);
            verify(r.y <= 0.001, "top edge uncovered for " + cases[i]);
            verify(r.x + r.width >= 5632 - 0.001, "right edge uncovered for " + cases[i]);
            verify(r.y + r.height >= 1584 - 0.001, "bottom edge uncovered for " + cases[i]);
        }
    }

    function test_the_rect_keeps_the_sources_aspect() {
        // This is the un-squash. A square mask drawn at the box's aspect is the
        // whole bug: the silhouette would be 3.5x too wide on this monitor.
        const r = ClockDepth.coverRect(3840, 1594, 5120, 1440);
        fuzzyCompare(r.width / r.height, 3840 / 1594, 0.0001);
    }

    function test_a_mask_at_the_pictures_own_aspect_lands_unstretched() {
        // Confirmed rather than assumed, because `coverRect` exists precisely
        // BECAUSE the salient models' masks are square while the wallpaper is
        // not - so a mask that is not square is the case the function was never
        // written for, and the obvious guess is that it needs a second path.
        //
        // It does not, and the reason is that the rect is a rectangle for the
        // WALLPAPER: the function never reads the mask's dimensions at all.
        // Stretching a mask into it lands every mask's own extent onto the
        // picture's own extent, so a mask that already carries the picture's
        // aspect is scaled by the same factor on both axes - it is not squashed
        // and then unsquashed, it is simply not squashed.
        const r = ClockDepth.coverRect(3840, 1594, 5120, 1440);
        // What MobileSAM returns for that picture: the longest side at 1024,
        // the aspect kept. tests/test_clock_depth_cache.py pins the producer to
        // exactly this size.
        const maskW = 1024, maskH = 425;
        fuzzyCompare(r.width / maskW, r.height / maskH, 0.005);
    }

    function test_the_square_mask_and_the_picture_shaped_one_share_one_rect() {
        // The half that would break if anyone "fixed" coverRect to take the
        // mask's size: one wallpaper has one cover rect, and both kinds of mask
        // are stretched into it. A per-mask rect is a second registration, and
        // the picker and the desktop layer draw through the same component
        // precisely so there cannot be two.
        // A 3.56:1 picture into a 4:3 box, deliberately: at a matching aspect
        // the box IS the cover rect and every registration bug is invisible,
        // which is the hole test_clock_depth_compositing.qml's fixture had.
        const wide = ClockDepth.coverRect(7680, 2160, 1600, 1200);
        const again = ClockDepth.coverRect(7680, 2160, 1600, 1200);
        compare(wide.width, again.width);
        compare(wide.height, again.height);
        // A square mask stretched into it is squashed by the picture's own
        // aspect ratio; a 1024x288 one is not. Both cover the same rectangle.
        fuzzyCompare(wide.width / wide.height, 7680 / 2160, 0.0001);
        fuzzyCompare(wide.width / 1024, wide.height / 288, 0.005);
    }

    // normalisedPoint: a click on a preview, as a point in the picture.

    function test_a_click_in_the_middle_of_the_picture_is_the_middle() {
        const r = ClockDepth.coverRect(3840, 1594, 5120, 1440);
        const p = ClockDepth.normalisedPoint(r, 2560, 720);
        fuzzyCompare(p.x, 0.5, 0.0001);
        fuzzyCompare(p.y, 0.5, 0.0001);
    }

    function test_the_crop_is_undone_by_the_same_rect_that_applied_it() {
        // The registration, run backwards. The picture overflows the box, so a
        // click at the box's left edge is NOT the picture's left edge - it is
        // wherever the crop starts, and getting this wrong sends the click to a
        // part of the wallpaper the user cannot see. Round-tripping is the check
        // that cannot be satisfied by a plausible-looking wrong formula.
        const r = ClockDepth.coverRect(3840, 1594, 5120, 1440);
        const cases = [[0.1, 0.2], [0.5, 0.5], [0.87, 0.04], [1, 1], [0, 0]];
        for (let i = 0; i < cases.length; i++) {
            const nx = cases[i][0], ny = cases[i][1];
            const p = ClockDepth.normalisedPoint(r,
                r.x + nx * r.width, r.y + ny * r.height);
            fuzzyCompare(p.x, nx, 0.0001, "x for " + cases[i]);
            fuzzyCompare(p.y, ny, 0.0001, "y for " + cases[i]);
        }
    }

    function test_a_click_at_the_boxs_edge_is_inside_the_picture_not_at_its_edge() {
        // 3840x1594 into 5120x1440 crops the top and bottom away, so the top of
        // the box is somewhere down the picture. A mapping that ignored the
        // rect's origin would answer 0 here and put every click too high.
        const r = ClockDepth.coverRect(3840, 1594, 5120, 1440);
        const p = ClockDepth.normalisedPoint(r, 0, 0);
        compare(p.x, 0);
        verify(p.y > 0.05, "top of the box maps to the top of the picture: " + p.y);
    }

    function test_a_click_outside_the_picture_is_clamped_rather_than_refused() {
        // The producer refuses a point outside the picture, so an off-by-a-pixel
        // at the frame's edge would reach the user as an error message about a
        // click that looked entirely ordinary.
        const r = ClockDepth.coverRect(1000, 1000, 500, 500);
        const p = ClockDepth.normalisedPoint(r, -40, 9000);
        compare(p.x, 0);
        compare(p.y, 1);
    }

    function test_an_empty_rect_answers_null_rather_than_a_point() {
        verify(ClockDepth.normalisedPoint({ x: 0, y: 0, width: 0, height: 0 }, 5, 5) === null);
        verify(ClockDepth.normalisedPoint(undefined, 5, 5) === null);
        verify(ClockDepth.normalisedPoint({ x: 0, y: 0, width: 100, height: 100 },
            NaN, 5) === null);
    }

    function test_an_unloaded_image_yields_the_box_rather_than_NaN() {
        // An Image's implicit size reads 0 until its source resolves, and a NaN
        // on x/y/width/height does not misplace the mask - it stops the item
        // rendering, which is indistinguishable from a wallpaper with no mask.
        const cases = [[0, 0], [0, 100], [100, 0], [-5, 10], [NaN, 10], [undefined, undefined]];
        for (let i = 0; i < cases.length; i++) {
            const r = ClockDepth.coverRect(cases[i][0], cases[i][1], 800, 600);
            verify(isFinite(r.x) && isFinite(r.y), "non-finite origin for " + cases[i]);
            verify(r.width > 0 && r.height > 0, "empty rect for " + cases[i]);
        }
    }
}
