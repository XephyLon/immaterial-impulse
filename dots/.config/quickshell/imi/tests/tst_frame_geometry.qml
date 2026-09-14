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
        compare(Geo.edgeInsets("top", 40, 5, "", 0), { top: 45, left: 5, right: 5, bottom: 5 });
        compare(Geo.edgeInsets("bottom", 40, 5, "", 0), { top: 5, left: 5, right: 5, bottom: 45 });
    }

    function test_a_pinned_dock_is_an_occupant_like_the_bar() {
        compare(Geo.edgeInsets("top", 40, 5, "bottom", 66), { top: 45, left: 5, right: 5, bottom: 71 });
        compare(Geo.edgeInsets("top", 40, 5, "left", 66), { top: 45, left: 71, right: 5, bottom: 5 });
        // Both on one edge add up: windows start after both zones.
        compare(Geo.edgeInsets("top", 40, 5, "top", 66), { top: 111, left: 5, right: 5, bottom: 5 });
        // An unpinned dock is no occupant (the caller passes no edge).
        compare(Geo.edgeInsets("top", 40, 5, "", 66), { top: 45, left: 5, right: 5, bottom: 5 });
    }

    function test_each_fillet_sits_at_its_inner_corner() {
        const insets = Geo.edgeInsets("top", 40, 5, "bottom", 66);
        compare(Geo.cornerMargins("topLeft", insets), { left: 5, top: 45, right: 0, bottom: 0 });
        compare(Geo.cornerMargins("topRight", insets), { left: 0, top: 45, right: 5, bottom: 0 });
        compare(Geo.cornerMargins("bottomLeft", insets), { left: 5, top: 0, right: 0, bottom: 71 });
        compare(Geo.cornerMargins("bottomRight", insets), { left: 0, top: 0, right: 5, bottom: 71 });
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

    function test_a_band_starts_under_its_edges_occupants() {
        compare(Geo.bandOffset("top", "top", 40, "", 0), 40);
        compare(Geo.bandOffset("bottom", "top", 40, "", 0), 0);
        compare(Geo.bandOffset("bottom", "top", 40, "bottom", 66), 66);
        compare(Geo.bandOffset("top", "top", 40, "top", 66), 106);
    }
}
