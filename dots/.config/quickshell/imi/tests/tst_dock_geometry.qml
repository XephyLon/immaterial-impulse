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

    function test_the_turn_is_a_size_rather_than_a_set_of_anchors() {
        // contentBox exists so an item that spans the dock's thickness never
        // has to change WHICH anchors it uses when the dock turns: the
        // thickness lands across the dock's own axis and the item's own
        // implicit size along it.
        const horizontal = Geometry.contentBox("bottom", 75, 613, 397);
        compare(horizontal.width, 613, "along the strip it is the icons' size");
        compare(horizontal.height, 75, "across it, the dock's whole thickness");
        const vertical = Geometry.contentBox("left", 75, 613, 397);
        compare(vertical.width, 75);
        compare(vertical.height, 397);
        // The two axes genuinely swap - the same call at opposite edges must
        // not agree on either dimension.
        verify(horizontal.width !== vertical.width
               && horizontal.height !== vertical.height);
        // An unknown edge is the dock we already ship, here too.
        const nonsense = Geometry.contentBox("diagonal", 75, 613, 397);
        compare(nonsense.width, horizontal.width);
        compare(nonsense.height, horizontal.height);
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

    // --- the two side edges -------------------------------------------------

    function test_thickness_is_the_same_arithmetic_on_either_axis() {
        // A vertical dock is 75px WIDE and reserves 65 of them. The dock's
        // `height` key keeps its name and means thickness at every edge, so
        // there is no second number to get wrong - only a different axis to
        // apply the one number to.
        for (const edge of ["top", "bottom", "left", "right"]) {
            compare(Geometry.thickness(dockHeight, elevation, gaps), 75,
                    edge + " is the same thickness");
            compare(Geometry.exclusiveZone(dockHeight, elevation, gaps), 65,
                    edge + " reserves the same");
        }
        // ...and the axis it lands on is the one the anchors leave free.
        for (const edge of ["left", "right"]) {
            const a = Geometry.anchors(edge);
            verify(a.top && a.bottom, edge + " spans the screen's height");
            verify(!(a.left && a.right), edge + " leaves its width to the thickness");
        }
    }

    function test_the_margin_pair_lands_on_the_horizontal_axis_at_a_side_edge() {
        // The asymmetry that is load-bearing for the blur region: the
        // elevation margin is inward (it is where the shadow is drawn), the
        // compositor's gap outward. At a side edge that pair is left/right.
        const left = Geometry.margins("left", elevation, gaps);
        compare(left.right, elevation, "the shadow falls toward the screen");
        compare(left.left, gaps, "and the compositor's gap toward the edge");
        const right = Geometry.margins("right", elevation, gaps);
        compare(right.left, elevation);
        compare(right.right, gaps);
        // Not merely different - genuinely swapped between the two.
        verify(left.left !== right.left && left.right !== right.right);
    }

    function test_inward_and_outward_are_one_relation_asked_four_ways() {
        compare(Geometry.inwardSide("bottom"), "top");
        compare(Geometry.inwardSide("left"), "right");
        compare(Geometry.outwardSide("left"), "left");
        // The reveal pushes the body OUTWARD from where it rests, and a popup
        // opens inward, so the two are one relation read in both directions.
        for (const edge of ["top", "bottom", "left", "right"]) {
            compare(Geometry.popupGravity(edge), Geometry.inwardSide(edge));
            const push = Geometry.hideDirection(edge);
            const outward = Geometry.outwardSide(edge);
            compare(push > 0, outward === "bottom" || outward === "right",
                    edge + " hides toward its own edge, not onto the screen");
        }
    }

    function test_a_directed_pair_never_touches_the_long_axis() {
        const left = Geometry.directedSides("left", 7, 3);
        compare(left.right, 7);
        compare(left.left, 3);
        compare(left.top, 0, "an inset on the long axis eats the strip, not its thickness");
        compare(left.bottom, 0);
        const bottom = Geometry.directedSides("bottom", 7, 3);
        compare(bottom.top, 7);
        compare(bottom.bottom, 3);
        compare(bottom.left, 0);
        compare(bottom.right, 0);
    }

    function test_a_surface_anchored_popup_takes_a_corner_and_a_direction() {
        // The window-preview popup hangs off the dock's whole surface, so one
        // side is not enough: it needs the corner it attaches to and the way
        // it grows. Both start inward - a popup opening into the screen edge
        // is a popup the compositor clips.
        const bottom = Geometry.popupAnchorSides("bottom");
        compare(bottom.edges, ["top", "left"]);
        compare(bottom.gravity, ["top", "right"]);
        const left = Geometry.popupAnchorSides("left");
        compare(left.edges, ["right", "top"]);
        compare(left.gravity, ["right", "bottom"]);
        const right = Geometry.popupAnchorSides("right");
        compare(right.edges, ["left", "top"]);
        compare(right.gravity, ["left", "bottom"]);
        for (const edge of ["top", "bottom", "left", "right"]) {
            const sides = Geometry.popupAnchorSides(edge);
            compare(sides.edges[0], Geometry.inwardSide(edge));
            compare(sides.gravity[0], Geometry.inwardSide(edge));
        }
    }

    function test_the_hover_lift_rises_out_of_the_dock_at_every_edge() {
        // -y only is correct at exactly one edge. At the top it drives the
        // icon into the screen edge; at a side edge it moves along the strip
        // instead of out of it.
        compare(Geometry.inwardVector("bottom"), { x: 0, y: -1 });
        compare(Geometry.inwardVector("top"), { x: 0, y: 1 });
        compare(Geometry.inwardVector("left"), { x: 1, y: 0 });
        compare(Geometry.inwardVector("right"), { x: -1, y: 0 });
        for (const edge of ["left", "right"])
            compare(Geometry.inwardVector(edge).y, 0,
                    edge + " must not lift along its own strip");
    }

    function test_the_bars_overloaded_pair_reads_as_an_edge() {
        // `bottom` stops meaning bottom once `vertical` is set. The dock only
        // needs this to notice it is being sent where an auto-hiding bar
        // already lives, and a comparison across two vocabularies means
        // nothing.
        compare(Geometry.barEdge(false, false), "top");
        compare(Geometry.barEdge(false, true), "bottom");
        compare(Geometry.barEdge(true, false), "left");
        compare(Geometry.barEdge(true, true), "right");
    }
}
