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
        compare(Geo.edgeInsets("top", 40, 5, ""), { top: 45, left: 5, right: 5, bottom: 5 });
        compare(Geo.edgeInsets("bottom", 40, 5, ""), { top: 5, left: 5, right: 5, bottom: 45 });
    }

    function test_the_docks_edge_is_left_to_the_dock() {
        compare(Geo.edgeInsets("top", 40, 5, "bottom"), { top: 45, left: 5, right: 5, bottom: 0 });
        compare(Geo.edgeInsets("top", 40, 5, "left"), { top: 45, left: 0, right: 5, bottom: 5 });
        // The dock on the bar's own edge changes nothing: the bar wins.
        compare(Geo.edgeInsets("top", 40, 5, "top"), { top: 45, left: 5, right: 5, bottom: 5 });
    }

    function test_each_fillet_sits_at_its_inner_corner_and_a_dock_corner_is_not_drawn() {
        const insets = Geo.edgeInsets("top", 40, 5, "");
        compare(Geo.cornerMargins("topLeft", insets), { left: 5, top: 45, right: 0, bottom: 0, draw: true });
        compare(Geo.cornerMargins("topRight", insets), { left: 0, top: 45, right: 5, bottom: 0, draw: true });
        compare(Geo.cornerMargins("bottomLeft", insets), { left: 5, top: 0, right: 0, bottom: 5, draw: true });
        compare(Geo.cornerMargins("bottomRight", insets), { left: 0, top: 0, right: 5, bottom: 5, draw: true });
        compare(Geo.cornerMargins("nowhere", insets), { left: 0, top: 0, right: 0, bottom: 0, draw: false });
        const docked = Geo.edgeInsets("top", 40, 5, "bottom");
        verify(!Geo.cornerMargins("bottomLeft", docked).draw, "no frame on the dock's edge, no fillet there");
        verify(Geo.cornerMargins("topLeft", docked).draw);
    }

    function test_the_inner_radius_is_concentric_with_the_window_corner() {
        compare(Geo.innerRadius(12, 5), 17);
        compare(Geo.innerRadius(0, 5), 5);
        compare(Geo.innerRadius(null, 5), 5);
    }

    function test_the_bar_edge_band_starts_under_the_bar() {
        compare(Geo.bandOffset("top", "top", 40), 40);
        compare(Geo.bandOffset("bottom", "top", 40), 0);
        compare(Geo.bandOffset("bottom", "bottom", 40), 40);
    }
}
