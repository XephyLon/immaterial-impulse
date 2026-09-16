import QtQuick
import QtTest
import "../services/frame_geometry.js" as Geo

// Frame mode's arithmetic, without the shell.
TestCase {
    name: "FrameGeometry"

    function test_band_thickness_falls_back_to_the_outer_gap() {
        compare(Geo.bandThickness(0, 5), 5);
        compare(Geo.bandThickness(12, 5), 12);
        compare(Geo.bandThickness(0, 0), 0);
        compare(Geo.bandThickness("8", "5"), 8);
        compare(Geo.bandThickness(null, undefined), 0);
    }

    function test_the_bar_edge_is_its_zone_plus_the_band_and_the_rest_is_the_band() {
        // The compositor reserves the bar's zone and then its outer gap:
        // windows start at zone + gap, so that is where the frame ends.
        compare(Geo.edgeInsets("top", 40, 5), { top: 45, left: 5, right: 5, bottom: 5 });
        compare(Geo.edgeInsets("bottom", 40, 5), { top: 5, left: 5, right: 5, bottom: 45 });
        compare(Geo.edgeInsets("top", "40", 5), { top: 45, left: 5, right: 5, bottom: 5 });
    }

    function test_the_dock_is_no_occupant_of_the_frame() {
        // The bar is the frame's only occupant. The dock meets the band on
        // its own terms (dock_geometry.js: on it, or a gap above it), so the
        // frame's inner corner on the dock's edge is at the band - a fillet
        // at the dock's inset arced into wallpaper, and a band as tall as
        // the dock's strip was a border with a pill lost in it.
        compare(Geo.edgeInsets.length, 3, "no dock parameters to pass");
        compare(Geo.bandMargins.length, 4);
        verify(Geo.bandExtent === undefined, "the band's extent is its thickness, nothing else");
        verify(Geo.bandOffset === undefined);
    }

    function test_each_fillet_sits_at_its_inner_corner() {
        const insets = Geo.edgeInsets("top", 40, 5);
        compare(Geo.cornerMargins("topLeft", insets), { left: 5, top: 45, right: 0, bottom: 0 });
        compare(Geo.cornerMargins("topRight", insets), { left: 0, top: 45, right: 5, bottom: 0 });
        compare(Geo.cornerMargins("bottomLeft", insets), { left: 5, top: 0, right: 0, bottom: 5 });
        compare(Geo.cornerMargins("bottomRight", insets), { left: 0, top: 0, right: 5, bottom: 5 });
        compare(Geo.cornerMargins("nowhere", insets), { left: 0, top: 0, right: 0, bottom: 0 });
    }

    function test_the_inner_radius_is_the_window_rounding() {
        // The fillet's box sits at the inset already; its arc is concentric
        // with the window's corner only when the radii are equal.
        compare(Geo.innerRadius(12), 12);
        compare(Geo.innerRadius(0), 0);
        compare(Geo.innerRadius(null), 0);
        compare(Geo.innerRadius(-3), 0);
    }

    function test_a_band_starts_under_the_bars_plate_and_at_the_screen_edge_elsewhere() {
        compare(Geo.bandStart("top", "top", 40), 40);
        compare(Geo.bandStart("bottom", "top", 40), 0);
        compare(Geo.bandStart("bottom", "bottom", 40), 40);
        compare(Geo.bandStart("left", "top", 40), 0);
    }

    function test_the_horizontal_bands_span_the_width_and_the_side_bands_run_between_them() {
        // Bar on top: the top band sits under the bar's plate, the bottom
        // band at the screen edge, both the full width; the side bands start
        // where the top band ends and stop where the bottom band starts.
        compare(Geo.bandMargins("top", "top", 40, 5), { top: 40, bottom: 0, left: 0, right: 0 });
        compare(Geo.bandMargins("bottom", "top", 40, 5), { top: 0, bottom: 0, left: 0, right: 0 });
        compare(Geo.bandMargins("left", "top", 40, 5), { top: 45, bottom: 5, left: 0, right: 0 });
        compare(Geo.bandMargins("right", "top", 40, 5), { top: 45, bottom: 5, left: 0, right: 0 });
        // Bar at the bottom: mirrored.
        compare(Geo.bandMargins("bottom", "bottom", 40, 5), { top: 0, bottom: 40, left: 0, right: 0 });
        compare(Geo.bandMargins("top", "bottom", 40, 5), { top: 0, bottom: 0, left: 0, right: 0 });
        compare(Geo.bandMargins("left", "bottom", 40, 5), { top: 5, bottom: 45, left: 0, right: 0 });
    }

    function test_no_two_bands_overlap() {
        // The frame's colour is translucent: a corner painted by two bands
        // is darker than the frame. Lay the four bands out on a 100x80
        // screen, bar on top, band 5, and check every pair.
        const band = 5, W = 100, H = 80;
        const rects = ["top", "bottom", "left", "right"].map(edge => {
            const m = Geo.bandMargins(edge, "top", 40, band);
            const horizontal = edge === "top" || edge === "bottom";
            return {
                edge,
                x: horizontal ? m.left : (edge === "left" ? 0 : W - band),
                y: horizontal ? (edge === "top" ? m.top : H - m.bottom - band) : m.top,
                w: horizontal ? W - m.left - m.right : band,
                h: horizontal ? band : H - m.top - m.bottom,
            };
        });
        for (let i = 0; i < rects.length; i++)
            for (let j = i + 1; j < rects.length; j++) {
                const a = rects[i], b = rects[j];
                const overlap = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
                verify(!overlap, a.edge + " and " + b.edge + " overlap");
            }
        // ...and they still meet: the left band runs from the top band's
        // bottom to the bottom band's top.
        compare(rects[2].y, rects[0].y + rects[0].h);
        compare(rects[2].y + rects[2].h, rects[1].y);
    }
}
