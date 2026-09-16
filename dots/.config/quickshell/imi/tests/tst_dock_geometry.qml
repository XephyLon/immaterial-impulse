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

    // --- frame mode ---------------------------------------------------------

    function test_in_frame_mode_the_dock_moves_in_by_the_band_it_meets() {
        // Outside frame mode: nowhere. In it, the SURFACE sits where the
        // attached tab needs it - the pill (gap inside its surface) on the
        // band: nothing to move at the default band, which IS the gap; in by
        // the difference when the band is thicker, OUT when it is thinner (a
        // negative margin, so the tab still sits on the band rather than a
        // sliver above it). Floating is not a second surface position any
        // more: the pill lifts INSIDE the surface (splitTravel), so the
        // switch never reconfigures the surface and can be drawn.
        compare(Geometry.frameOffset(false, 12, gaps), 0);
        compare(Geometry.frameOffset(true, 5, gaps), 0, "the default band is the gap: the tab is already on it");
        compare(Geometry.frameOffset(true, 12, gaps), 7);
        compare(Geometry.frameOffset(true, 2, gaps), -3);
        compare(Geometry.frameOffset(true, "12", "5"), 7);
        // The compositor adds an anchored-edge margin to the zone itself, so
        // the reservation is untouched by the move.
        compare(Geometry.exclusiveZone(dockHeight, elevation, gaps), 65);
    }

    // --- the split (docs/proposals/motion-split.md §6) -------------------------

    function test_the_lift_is_the_compositor_gap_and_only_while_the_frame_is_on() {
        // Floating = a gap above the band, attached = on it: the travel between
        // the two is the gap, whatever the band's thickness. Outside frame mode
        // there is nothing to lift off, and an unpinned dock never reserves,
        // so it never lifts (its hover sliver stays at the edge).
        compare(Geometry.splitTravel(true, true, gaps), 5);
        compare(Geometry.splitTravel(true, true, 12), 12);
        compare(Geometry.splitTravel(false, true, gaps), 0);
        compare(Geometry.splitTravel(true, false, gaps), 0);
        compare(Geometry.splitTravel(true, true, "5"), 5);
    }

    function test_the_zone_grows_by_the_gap_when_the_dock_floats() {
        // The surface no longer moves for the switch, so the reservation is
        // what keeps windows the same distance from a floating pill as before:
        // offset + zone + lift is band + height + gap either way.
        compare(Geometry.splitZoneExtra(true, true, gaps), 0, "attached reserves what it always did");
        compare(Geometry.splitZoneExtra(true, false, gaps), 5, "floating reserves the lift too");
        compare(Geometry.splitZoneExtra(false, false, gaps), 0);
        const band = 12;
        const attachedWindows = Geometry.frameOffset(true, band, gaps) + Geometry.exclusiveZone(dockHeight, elevation, gaps) + Geometry.splitZoneExtra(true, true, gaps);
        const floatingWindows = Geometry.frameOffset(true, band, gaps) + Geometry.exclusiveZone(dockHeight, elevation, gaps) + Geometry.splitZoneExtra(true, false, gaps);
        compare(attachedWindows, dockHeight + band, "attached: windows end height + band from the edge, as #396 measured");
        compare(floatingWindows, dockHeight + band + gaps, "floating: a gap further, as #396's moved surface gave");
    }

    function test_the_lift_room_is_the_elevation_margin_or_the_dock_grows() {
        // The pill lifts into its own inward elevation margin. A gap bigger
        // than that margin would push it out of its surface, so the dock
        // grows by exactly the shortfall - nothing at all at the defaults.
        compare(Geometry.splitRoom(gaps, elevation), 0);
        compare(Geometry.splitRoom(10, elevation), 0);
        compare(Geometry.splitRoom(20, elevation), 10);
        compare(Geometry.splitRoom("20", "10"), 10);
    }

    function test_a_lifted_pill_keeps_its_margins_summing_to_the_thickness() {
        // The outward margin grows by the lift and the inward one shrinks by
        // it (plus the room, which only exists when the gap outgrows the
        // elevation): the pill moves, the strip's thickness does not.
        const rest = Geometry.margins("bottom", elevation, gaps);
        const lifted = Geometry.liftedMargins("bottom", rest, 0, 3);
        compare(lifted.top, elevation - 3);
        compare(lifted.bottom, gaps + 3);
        compare(lifted.left, 0);
        compare(lifted.right, 0);
        compare(lifted.top + lifted.bottom, rest.top + rest.bottom, "the sum is the sum");
        const roomy = Geometry.liftedMargins("bottom", rest, 10, 0);
        compare(roomy.top, elevation + 10, "the room sits inward, so the pill stays where it was");
        compare(roomy.bottom, gaps);
        // Directed, so the same call is right at every edge.
        const top = Geometry.liftedMargins("top", Geometry.margins("top", elevation, gaps), 0, 3);
        compare(top.top, gaps + 3); compare(top.bottom, elevation - 3);
        const left = Geometry.liftedMargins("left", Geometry.margins("left", elevation, gaps), 0, 3);
        compare(left.left, gaps + 3); compare(left.right, elevation - 3); compare(left.top, 0);
        const right = Geometry.liftedMargins("right", Geometry.margins("right", elevation, gaps), 0, 3);
        compare(right.right, gaps + 3); compare(right.left, elevation - 3);
    }

    function test_the_icons_ride_the_pill() {
        // The strip is centred in the dock's box; the pill is not, once it has
        // lifted (or the box has room). The icons take the difference as a
        // centre offset along the dock's across axis: inward by the lift,
        // outward by half the room.
        compare(Geometry.liftOffset("bottom", 0, 5), { x: 0, y: -5 });
        compare(Geometry.liftOffset("top", 0, 5), { x: 0, y: 5 });
        compare(Geometry.liftOffset("left", 0, 5), { x: 5, y: 0 });
        compare(Geometry.liftOffset("right", 0, 5), { x: -5, y: 0 });
        compare(Geometry.liftOffset("bottom", 10, 0), { x: 0, y: 5 });
        compare(Geometry.liftOffset("bottom", 10, 5), { x: 0, y: 0 });
    }

    function test_the_outward_corners_round_with_the_lift() {
        // Fused, the seam is square; free, the pill is a pill; between, the
        // outward pair rounds with the scalar and the inward pair never moves.
        const r = 22;
        compare(Geometry.cornerRadiiAt("bottom", r, 0), { topLeft: r, topRight: r, bottomLeft: 0, bottomRight: 0 });
        compare(Geometry.cornerRadiiAt("bottom", r, 0.5), { topLeft: r, topRight: r, bottomLeft: 11, bottomRight: 11 });
        compare(Geometry.cornerRadiiAt("bottom", r, 1), { topLeft: r, topRight: r, bottomLeft: r, bottomRight: r });
        compare(Geometry.cornerRadiiAt("top", r, 0.25), { topLeft: 5.5, topRight: 5.5, bottomLeft: r, bottomRight: r });
        compare(Geometry.cornerRadiiAt("left", r, 0.5), { topLeft: 11, topRight: r, bottomLeft: 11, bottomRight: r });
        compare(Geometry.cornerRadiiAt("right", r, 0.5), { topLeft: r, topRight: 11, bottomLeft: r, bottomRight: 11 });
        // Past the ends is the ends: a curve that leaves the unit box must not
        // produce a negative radius or a corner rounder than the pill.
        compare(Geometry.cornerRadiiAt("bottom", r, -0.2), Geometry.cornerRadiiAt("bottom", r, 0));
        compare(Geometry.cornerRadiiAt("bottom", r, 1.3), Geometry.cornerRadiiAt("bottom", r, 1));
        // The boolean form is the two ends of the same function.
        for (const edge of ["top", "bottom", "left", "right"]) {
            compare(Geometry.cornerRadii(edge, r, true), Geometry.cornerRadiiAt(edge, r, 0), edge);
            compare(Geometry.cornerRadii(edge, r, false), Geometry.cornerRadiiAt(edge, r, 1), edge);
        }
    }

    function test_the_neck_bridges_the_reach_and_narrows_to_nothing() {
        // The reference's neck exists while the outlines are within 40% of
        // the travelling body's thickness. The dock's lift is 5 px on a 60 px
        // pill, so the reach is the whole travel and the neck breaks at rest;
        // a body travelling further than 40% of itself breaks part way.
        compare(Geometry.neckReach(60, 5, 0.4), 5);
        compare(Geometry.neckReach(60, 40, 0.4), 24);
        compare(Geometry.neckReach(60, 0, 0.4), 0, "no travel, no neck");
        // The waist: the pill's full width when fused, nothing at the reach.
        compare(Geometry.neckWaist(400, 0, 5), 400);
        compare(Geometry.neckWaist(400, 2.5, 5), 200);
        compare(Geometry.neckWaist(400, 5, 5), 0);
        compare(Geometry.neckWaist(400, 7, 5), 0, "past the reach the bridge is broken");
        compare(Geometry.neckWaist(400, 1, 0), 0, "a zero reach never bridges");
    }

    function test_the_neck_sits_between_the_pill_and_the_band_at_every_edge() {
        // The neck's box, from the pill's box: it fills the lift between the
        // pill's outward edge and where the band is (the pill's REST outward
        // edge), centred along the strip at the waist's width.
        const pill = { x: 100, y: 5, width: 400, height: 60 };
        const bottom = Geometry.neckBox("bottom", pill, 4, 200);
        compare(bottom, { x: 200, y: 65, width: 200, height: 4 });
        const top = Geometry.neckBox("top", pill, 4, 200);
        compare(top, { x: 200, y: 1, width: 200, height: 4 });
        const side = { x: 5, y: 100, width: 60, height: 400 };
        compare(Geometry.neckBox("left", side, 4, 200), { x: 1, y: 200, width: 4, height: 200 });
        compare(Geometry.neckBox("right", side, 4, 200), { x: 65, y: 200, width: 4, height: 200 });
        // Its two flanks are fillets whose straight edges hug the band and the
        // waist: for a bottom dock the start (left) flank fills its box's
        // bottom-right and the end (right) flank its bottom-left.
        compare(Geometry.neckFilletCorners("bottom"), { start: "bottomRight", end: "bottomLeft" });
        compare(Geometry.neckFilletCorners("top"), { start: "topRight", end: "topLeft" });
        compare(Geometry.neckFilletCorners("left"), { start: "bottomLeft", end: "topLeft" });
        compare(Geometry.neckFilletCorners("right"), { start: "bottomRight", end: "topRight" });
        // Where each fillet's box sits, in the neck's own frame: against the
        // band (the neck's far side) and just outside the waist.
        compare(Geometry.neckFilletOffsets("bottom", 200, 4, 4), { start: { x: -4, y: 0 }, end: { x: 200, y: 0 } });
        compare(Geometry.neckFilletOffsets("bottom", 200, 6, 4), { start: { x: -4, y: 2 }, end: { x: 200, y: 2 } });
        compare(Geometry.neckFilletOffsets("top", 200, 6, 4), { start: { x: -4, y: 0 }, end: { x: 200, y: 0 } });
        compare(Geometry.neckFilletOffsets("left", 6, 200, 4), { start: { x: 0, y: -4 }, end: { x: 0, y: 200 } });
        compare(Geometry.neckFilletOffsets("right", 6, 200, 4), { start: { x: 2, y: -4 }, end: { x: 2, y: 200 } });
        // The fillet is as big as the lift and never wider than the flank room.
        compare(Geometry.neckFilletSize(4, 400, 200), 4);
        compare(Geometry.neckFilletSize(40, 400, 380), 10);
        compare(Geometry.neckFilletSize(4, 400, 400), 0, "no flank, no fillet");
    }

    function test_an_attached_dock_squares_only_its_outward_corners() {
        const r = 22;
        compare(Geometry.cornerRadii("bottom", r, false), { topLeft: r, topRight: r, bottomLeft: r, bottomRight: r });
        compare(Geometry.cornerRadii("bottom", r, true), { topLeft: r, topRight: r, bottomLeft: 0, bottomRight: 0 });
        compare(Geometry.cornerRadii("top", r, true), { topLeft: 0, topRight: 0, bottomLeft: r, bottomRight: r });
        compare(Geometry.cornerRadii("left", r, true), { topLeft: 0, topRight: r, bottomLeft: 0, bottomRight: r });
        compare(Geometry.cornerRadii("right", r, true), { topLeft: r, topRight: 0, bottomLeft: r, bottomRight: 0 });
        // The seam is always the outward side, at every edge.
        for (const edge of ["top", "bottom", "left", "right"]) {
            const radii = Geometry.cornerRadii(edge, r, true);
            const out = Geometry.outwardSide(edge);
            const squared = Object.keys(radii).filter(k => radii[k] === 0);
            compare(squared.length, 2, edge + " squares exactly two corners");
            for (const k of squared)
                verify(k.toLowerCase().indexOf(out) !== -1, edge + ": " + k + " is not on the " + out + " side");
        }
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
