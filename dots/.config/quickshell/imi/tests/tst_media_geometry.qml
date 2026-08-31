import QtTest
import "../modules/common/plugins/bundled/nandoroid-media/media_geometry.js" as Geometry

// The media widget's shared-element geometry, scored against the numbers
// measured off the three current layouts. Spans in scaled pixels at scale 1:
// 3x2 = 420x228, 2x2 = 276x228, 2x1 = 276x108 (Appearance.widgetGridSpan*).
//
// These are the rects step 4's one tree will bind, so every value asserted
// here is a value the play button will actually travel to. Cross-span
// relationships matter as much as the absolutes - the whole point is that
// prev at 3x2 and prev at 2x1 are the same element in two places.
TestCase {
    name: "MediaGeometryTest"

    // ---- 3x2 -------------------------------------------------------------

    function test_3x2_slider_is_bottom_anchored_and_centred() {
        const slider = Geometry.progressRect("3x2", 420, 228, 1);
        compare(slider.width, 170);
        compare(slider.height, 12);
        compare(slider.x, 125, "(420 - 170) / 2");
        compare(slider.y, 228 - 22 - 12, "bottom margin 22, then its own height");
    }

    function test_3x2_transport_row_is_centred_and_sized_as_authored() {
        const t = Geometry.transportRects("3x2", 420, 228, 1);
        compare(t.prev.width, 62);
        compare(t.play.width, 192);
        compare(t.play.height, 66);
        compare(t.next.width, 62);
        // row: 62 + 12 + 192 + 12 + 62 = 340, centred in 420.
        compare(t.prev.x, 40);
        compare(t.play.x, 114);
        compare(t.next.x, 318);
    }

    function test_3x2_transport_sits_above_the_time_slot_and_slider() {
        const t = Geometry.transportRects("3x2", 420, 228, 1);
        const time = Geometry.timeLabelRect("3x2", 420, 228, 1);
        const slider = Geometry.progressRect("3x2", 420, 228, 1);
        compare(time.y + time.height + 2, slider.y, "time slot, spacing 2, slider");
        compare(t.play.y + t.play.height + 2, time.y, "play, spacing 2, time slot");
        verify(t.play.y > 0, "the row stays inside the card");
    }

    function test_3x2_prev_and_next_are_vertically_centred_on_the_play_pill() {
        const t = Geometry.transportRects("3x2", 420, 228, 1);
        compare(t.prev.y - t.play.y, (66 - 62) / 2);
        compare(t.prev.y, t.next.y);
    }

    function test_3x2_has_no_artwork() {
        compare(Geometry.artworkRect("3x2", 420, 228, 1), null,
                "null is a fade, never a morph");
    }

    // ---- 2x2 -------------------------------------------------------------

    function test_2x2_frame_is_the_cookie_layouts_frame() {
        const frame = Geometry.cookieFrame(276, 228, 1);
        compare(frame.size, 204, "min(276, 228) - 2 * 12");
        compare(frame.x, 36);
        compare(frame.y, 12);
    }

    function test_2x2_badges_sit_on_the_frames_corners() {
        const t = Geometry.transportRects("2x2", 276, 228, 1);
        const frame = Geometry.cookieFrame(276, 228, 1);
        compare(t.prev.x, frame.x);
        compare(t.prev.y, frame.y);
        fuzzyCompare(t.next.x, frame.x + frame.size - t.next.width, 0.001);
        fuzzyCompare(t.prev.width, 204 * 64 / 230, 0.001, "the clock's badge ratio");
    }

    function test_2x2_play_is_the_cookie_and_holds_the_artwork() {
        // The button IS the cookie frame, and the artwork is its interior -
        // the review's design: art appears from within the play button.
        const t = Geometry.transportRects("2x2", 276, 228, 1);
        const frame = Geometry.cookieFrame(276, 228, 1);
        compare(t.play.x, frame.x);
        compare(t.play.width, frame.size);
        const art = Geometry.artworkRect("2x2", 276, 228, 1);
        fuzzyCompare(art.width, 204 * 0.72, 0.001);
        fuzzyCompare(art.x + art.width / 2, t.play.x + t.play.width / 2, 0.001,
                     "the artwork is centred in the button");
    }

    function test_2x2_progress_is_the_circle_inside_the_play_button() {
        // The review's words: a perfect circle inside the play button,
        // between the artwork (0.72 of the frame) and the cookie's valleys.
        const progress = Geometry.progressRect("2x2", 276, 228, 1);
        const play = Geometry.transportRects("2x2", 276, 228, 1).play;
        const art = Geometry.artworkRect("2x2", 276, 228, 1);
        fuzzyCompare(progress.width, 204 * 0.76, 0.001);
        verify(progress.width > art.width, "outside the artwork");
        verify(progress.width < play.width, "inside the button");
        fuzzyCompare(progress.x + progress.width / 2, play.x + play.width / 2, 0.001,
                     "concentric with the button");
    }

    // ---- 2x1 -------------------------------------------------------------

    function test_2x1_row_is_centred_with_the_authored_sizes() {
        const t = Geometry.transportRects("2x1", 276, 108, 1);
        compare(t.prev.width, 56);
        compare(t.play.width, 72);
        // row: 56 + 12 + 72 + 12 + 56 = 208, centred in 276.
        compare(t.prev.x, 34);
        compare(t.play.x, 102);
        compare(t.next.x, 186);
        compare(t.play.y, 18, "(108 - 72) / 2");
        compare(t.prev.y, 26, "(108 - 56) / 2");
    }

    function test_2x1_progress_floats_just_outside_the_play_button() {
        // The ring is the button's border, floating with a margin rather
        // than stuck to its edge - concentric, and wider by the margin ratio
        // on every side.
        const t = Geometry.transportRects("2x1", 276, 108, 1);
        const progress = Geometry.progressRect("2x1", 276, 108, 1);
        fuzzyCompare(progress.x + progress.width / 2, t.play.x + t.play.width / 2, 0.001,
                     "concentric with the button");
        verify(progress.width > t.play.width, "outside the button");
        fuzzyCompare(progress.width, t.play.width * 1.28, 0.01);
    }

    // ---- 1x1 -------------------------------------------------------------

    function test_1x1_sides_flank_the_play_flush() {
        // The redesign (2026-08-31): half-pill prev/next STUCK to the play
        // button's sides - round edge outward, flat edge against it - the
        // row lifted to make room for the seek bar below.
        const t = Geometry.transportRects("1x1", 132, 108, 1);
        compare(t.prev.width, 22);
        compare(t.prev.height, 34);
        compare(t.play.width, 48);
        compare(t.prev.x + t.prev.width, t.play.x, "prev is flush against play");
        compare(t.play.x + t.play.width, t.next.x, "next is flush against play");
        compare(t.prev.x, (132 - (22 + 48 + 22)) / 2, "the trio is centred");
        compare(t.prev.y - t.play.y, (48 - 34) / 2, "sides centred on play");
    }

    function test_1x1_row_sits_above_its_seek_bar() {
        const t = Geometry.transportRects("1x1", 132, 108, 1);
        const seek = Geometry.progressRect("1x1", 132, 108, 1);
        compare(seek.height, 16);
        compare(seek.y + seek.height, 108 - 8, "seek rides 8 above the bottom");
        compare(seek.x, 16);
        compare(seek.width, 132 - 32);
        compare(t.play.y + t.play.height, seek.y - 8, "the row sits 8 above the seek");
    }

    function test_1x1_still_shows_no_time_no_button_artwork() {
        compare(Geometry.timeLabelRect("1x1", 132, 108, 1), null);
        compare(Geometry.artworkRect("1x1", 132, 108, 1), null);
    }

    // ---- cross-span, and scale -------------------------------------------

    function test_every_span_has_the_full_transport_set() {
        for (const span of ["3x2", "2x2", "2x1", "1x1"]) {
            const t = Geometry.transportRects(span, 276, 108, 1);
            verify(t.prev && t.play && t.next,
                   span + ": a shared element exists at every span");
        }
    }

    function test_an_unknown_span_returns_null_rather_than_a_guess() {
        compare(Geometry.transportRects("4x4", 400, 400, 1), null);
        compare(Geometry.progressRect("4x4", 400, 400, 1), null);
    }

    function test_scale_multiplies_sizes_and_preserves_centring() {
        const at1 = Geometry.transportRects("2x1", 276, 108, 1);
        const at2 = Geometry.transportRects("2x1", 552, 216, 2);
        compare(at2.play.width, at1.play.width * 2);
        compare(at2.play.x, at1.play.x * 2, "a doubled box doubles the centring");
        const slider2 = Geometry.progressRect("3x2", 840, 456, 2);
        compare(slider2.y, (228 - 34) * 2);
    }
}
