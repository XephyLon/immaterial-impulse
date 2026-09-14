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

    function test_the_bar_edge_is_the_bar_and_the_rest_is_the_band() {
        compare(Geo.edgeInsets("top", 40, 5), { top: 40, left: 5, right: 5, bottom: 5 });
        compare(Geo.edgeInsets("bottom", 40, 5), { top: 5, left: 5, right: 5, bottom: 40 });
    }

    function test_each_fillet_sits_at_its_inner_corner() {
        const insets = Geo.edgeInsets("top", 40, 5);
        compare(Geo.cornerMargins("topLeft", insets), { left: 5, top: 40, right: 0, bottom: 0 });
        compare(Geo.cornerMargins("topRight", insets), { left: 0, top: 40, right: 5, bottom: 0 });
        compare(Geo.cornerMargins("bottomLeft", insets), { left: 5, top: 0, right: 0, bottom: 5 });
        compare(Geo.cornerMargins("bottomRight", insets), { left: 0, top: 0, right: 5, bottom: 5 });
        compare(Geo.cornerMargins("nowhere", insets), { left: 0, top: 0, right: 0, bottom: 0 });
    }
}
