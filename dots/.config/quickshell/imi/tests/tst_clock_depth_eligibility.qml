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
