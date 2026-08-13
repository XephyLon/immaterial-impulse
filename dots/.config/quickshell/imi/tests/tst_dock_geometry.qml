import QtTest
import "../modules/imi/dock/dock_geometry.js" as Geometry

// Where the dock sits on each edge. The numbers are the part a test can
// reach; the measured baseline below is what a regression has to argue with.
TestCase {
    name: "DockGeometryTest"

    // The real defaults: dock.height 60, elevationMargin 10 (spacing.space125),
    // hyprlandGapsOut 5. Read back live from the compositor at those values,
    // `hyprctl monitors` reports reserved [0, 45, 0, 65] and a 5120x75 dock -
    // so 75 and 65 below are measurements, not arithmetic that happens to
    // agree with itself.
    readonly property real dockHeight: 60
    readonly property real elevation: 10
    readonly property real gaps: 5

    function test_the_reserved_zone_matches_the_measured_baseline() {
        compare(Geometry.exclusiveZone(dockHeight, elevation, gaps), 65,
                "the bottom dock's measured reservation");
        // Whatever the edge, the same arithmetic: the zone is a property of
        // the dock's thickness, not of which side it is on.
        compare(Geometry.thickness(dockHeight, elevation, gaps), 75,
                "and the dock's own measured size across its axis");
    }

    function test_every_edge_anchors_both_ends_of_its_long_axis() {
        const bottom = Geometry.anchors("bottom");
        verify(bottom.left && bottom.right && bottom.bottom && !bottom.top);
        const top = Geometry.anchors("top");
        verify(top.left && top.right && top.top && !top.bottom);
        const left = Geometry.anchors("left");
        verify(left.top && left.bottom && left.left && !left.right);
        const right = Geometry.anchors("right");
        verify(right.top && right.bottom && right.right && !right.left);
    }

    function test_the_margins_flip_with_the_edge() {
        // The asymmetry is the point: an elevation margin INWARD for the drop
        // shadow, the compositor's gap OUTWARD. A mirror that keeps the pair
        // in place puts the shadow off-screen.
        const bottom = Geometry.margins("bottom", elevation, gaps);
        compare(bottom.top, elevation);
        compare(bottom.bottom, gaps);
        const top = Geometry.margins("top", elevation, gaps);
        compare(top.top, gaps);
        compare(top.bottom, elevation);
        const left = Geometry.margins("left", elevation, gaps);
        compare(left.left, gaps);
        compare(left.right, elevation);
        const right = Geometry.margins("right", elevation, gaps);
        compare(right.left, elevation);
        compare(right.right, gaps);
    }

    function test_the_margin_pair_never_lands_on_the_long_axis() {
        for (const edge of ["top", "bottom"]) {
            const m = Geometry.margins(edge, elevation, gaps);
            compare(m.left, 0, edge + " has no horizontal inset");
            compare(m.right, 0);
        }
        for (const edge of ["left", "right"]) {
            const m = Geometry.margins(edge, elevation, gaps);
            compare(m.top, 0, edge + " has no vertical inset");
            compare(m.bottom, 0);
        }
    }

    function test_the_reveal_is_one_number_at_every_edge() {
        // hoverRegionHeight is 2 by default: the sliver is deliberately thin.
        const offsets = Geometry.revealOffsets(75, 2);
        compare(offsets.revealed, 0);
        compare(offsets.peeking, 73, "a sliver the pointer can still hit");
        compare(offsets.hidden, 76, "one past gone - stopping at the edge leaves a lit seam");
        verify(Geometry.hideDirection("bottom") > 0);
        verify(Geometry.hideDirection("top") < 0);
        verify(Geometry.hideDirection("right") > 0);
        verify(Geometry.hideDirection("left") < 0);
    }

    function test_a_popup_opens_away_from_the_edge() {
        compare(Geometry.popupGravity("bottom"), "top");
        compare(Geometry.popupGravity("top"), "bottom");
        compare(Geometry.popupGravity("left"), "right");
        compare(Geometry.popupGravity("right"), "left");
    }

    function test_an_unknown_edge_is_the_dock_we_already_ship() {
        // A preset written before this setting existed, or a hand-edited
        // config, must not produce an unanchored dock.
        compare(Geometry.normalizedEdge("sideways"), "bottom");
        compare(Geometry.popupGravity(""), "top");
        const anchors = Geometry.anchors(undefined);
        verify(anchors.bottom && anchors.left && anchors.right);
    }

    function test_vertical_is_only_the_two_side_edges() {
        verify(Geometry.isVertical("left") && Geometry.isVertical("right"));
        verify(!Geometry.isVertical("top") && !Geometry.isVertical("bottom"));
    }
}
