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

    function test_the_zone_reserves_the_union_of_where_the_pill_is_and_where_it_goes() {
        // The surface no longer moves for the switch, so the reservation is
        // what keeps windows a gap away from a floating pill. It steps at the
        // START of a lift (windows move away, the pill lifts into the space)
        // and at the END of a landing (the pill lands, then the windows
        // follow it in) - never mid-flight, and never while the pill is up:
        // stepping at the start of a landing put the windows against the
        // still-floating pill for the length of the motion.
        compare(Geometry.splitZoneExtra(5, false, 0), 0, "attached, at rest: what it always reserved");
        compare(Geometry.splitZoneExtra(5, true, 0), 5, "the lift is asked for: reserve it before the pill moves");
        compare(Geometry.splitZoneExtra(5, true, 1), 5, "floating, at rest");
        compare(Geometry.splitZoneExtra(5, false, 1), 5, "the landing is asked for: hold it while the pill is up");
        compare(Geometry.splitZoneExtra(5, false, 0.3), 5, "...all the way down");
        compare(Geometry.splitZoneExtra(0, true, 1), 0, "no lift (unpinned, or the frame off): nothing to reserve");
        const band = 12;
        const attachedWindows = Geometry.frameOffset(true, band, gaps) + Geometry.exclusiveZone(dockHeight, elevation, gaps) + Geometry.splitZoneExtra(gaps, false, 0);
        const floatingWindows = Geometry.frameOffset(true, band, gaps) + Geometry.exclusiveZone(dockHeight, elevation, gaps) + Geometry.splitZoneExtra(gaps, true, 1);
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

    function test_the_outward_corners_round_from_the_seam_to_the_pinch() {
        // Fused, the seam is square; free, the pill is a pill. The outward
        // pair rounds over the NECK'S span - from the seam, where the
        // outlines part, to the pinch-off - so the corner is round by the
        // time the flank has fully exposed it; rounding to rest instead left
        // a square corner hovering over a lit gap. The inward pair never
        // moves.
        const r = 22;
        const seam = 0.5, reach = 0.8;
        compare(Geometry.cornerRadiiAt("bottom", r, 0, seam, reach), { topLeft: r, topRight: r, bottomLeft: 0, bottomRight: 0 });
        compare(Geometry.cornerRadiiAt("bottom", r, 0.5, seam, reach), { topLeft: r, topRight: r, bottomLeft: 0, bottomRight: 0 }, "square until the seam");
        compare(Geometry.cornerRadiiAt("bottom", r, 0.7, seam, reach), { topLeft: r, topRight: r, bottomLeft: 11, bottomRight: 11 }, "half way to the pinch");
        compare(Geometry.cornerRadiiAt("bottom", r, 0.9, seam, reach), { topLeft: r, topRight: r, bottomLeft: r, bottomRight: r }, "round at the pinch");
        compare(Geometry.cornerRadiiAt("bottom", r, 1, seam, reach), { topLeft: r, topRight: r, bottomLeft: r, bottomRight: r });
        compare(Geometry.cornerRadiiAt("top", r, 0.6, seam, reach), { topLeft: 5.5, topRight: 5.5, bottomLeft: r, bottomRight: r });
        compare(Geometry.cornerRadiiAt("left", r, 0.7, seam, reach), { topLeft: 11, topRight: r, bottomLeft: 11, bottomRight: r });
        compare(Geometry.cornerRadiiAt("right", r, 0.7, seam, reach), { topLeft: r, topRight: 11, bottomLeft: r, bottomRight: 11 });
        // A look with no lift has no seam and no neck: the whole scalar is the rounding.
        compare(Geometry.cornerRadiiAt("bottom", r, 0.5, 0, 1), { topLeft: r, topRight: r, bottomLeft: 11, bottomRight: 11 });
        // Past the ends is the ends: a curve that leaves the unit box must not
        // produce a negative radius or a corner rounder than the pill.
        compare(Geometry.cornerRadiiAt("bottom", r, -0.2, seam, reach), Geometry.cornerRadiiAt("bottom", r, 0, seam, reach));
        compare(Geometry.cornerRadiiAt("bottom", r, 1.3, seam, reach), Geometry.cornerRadiiAt("bottom", r, 1, seam, reach));
        // The boolean form is the two ends of the same function.
        for (const edge of ["top", "bottom", "left", "right"]) {
            compare(Geometry.cornerRadii(edge, r, true), Geometry.cornerRadiiAt(edge, r, 0, seam, reach), edge);
            compare(Geometry.cornerRadii(edge, r, false), Geometry.cornerRadiiAt(edge, r, 1, seam, reach), edge);
        }
    }

    function test_the_neck_bridges_the_near_half_of_the_settle_and_narrows_to_nothing() {
        // The reference's neck lives from the seam to a pinch-off part way
        // through the settle half (165 ms of 800: the seam at 0.5 of the time,
        // the pinch at 0.7, which on this front-loaded curve is 0.9 of the
        // VALUE), never to rest - the bodies settle APART. `reach` is the
        // fraction of the settle half the neck bridges: the pill's full width
        // at the seam, nothing at the pinch.
        const seam = 0.5, reach = 0.8;
        compare(Geometry.neckWaist(400, 0, seam, reach), 400, "fused: the bridge is the pill");
        compare(Geometry.neckWaist(400, 0.5, seam, reach), 400, "at the seam, still the pill");
        compare(Geometry.neckWaist(400, 0.7, seam, reach), 200);
        compare(Geometry.neckWaist(400, 0.9, seam, reach), 0, "the pinch-off");
        compare(Geometry.neckWaist(400, 0.95, seam, reach), 0, "apart, settling");
        compare(Geometry.neckWaist(400, 1, seam, reach), 0);
        compare(Geometry.neckWaist(400, 0.6, seam, 0), 0, "a zero reach never bridges");
    }

    function test_a_reversal_takes_a_proportional_time_never_under_the_effects_tier() {
        // The source's rule (motion-split.md §1): a direction started from
        // part way takes the tier's duration times the distance left, with
        // a floor - here the effects tier - so a lift reversed at 10% does
        // not crawl back over the whole 800 ms and a reversal at 1% is not
        // a jump.
        compare(Geometry.splitDuration(800, 133, 0, 1), 800, "a whole direction is the tier");
        compare(Geometry.splitDuration(800, 133, 1, 0), 800);
        compare(Geometry.splitDuration(800, 133, 0.5, 1), 400, "half the way, half the time");
        compare(Geometry.splitDuration(800, 133, 0.1, 0), 133, "the floor");
        compare(Geometry.splitDuration(800, 133, 0.9, 0.9), 133, "no distance is still the floor");
        compare(Geometry.splitDuration(800, 133, 1.2, 0), 800, "a scalar past the unit box is clamped to a whole direction");
    }

    function test_the_blend_grows_to_the_seam_and_is_nothing_at_rest() {
        // The neck is a distance-field blend (motion-split.md §1, §6): a
        // smooth-minimum of the pill's and the band's fields whose radius is
        // the neck. It is ZERO at rest - a blend against a fused tab would
        // fillet its sides where the Rectangle draws none, a pop at the hand-
        // over - and grows to its full value at the seam, scaled by the lift
        // (the gap it has to bridge: a smooth-minimum bridges a gap of g
        // once its radius passes 2g). Past the pinch the waist is 0 and the
        // blend has nothing to act on.
        compare(Geometry.neckBlend(5, 0, 0.5), 0, "at rest, nothing");
        compare(Geometry.neckBlend(5, 0.25, 0.5), 10, "halfway to the seam, half the blend");
        compare(Geometry.neckBlend(5, 0.5, 0.5), 20, "at the seam, four lifts");
        compare(Geometry.neckBlend(5, 0.8, 0.5), 20, "held through the settle; the waist does the narrowing");
        compare(Geometry.neckBlend(0, 0.5, 0.5), 0, "no lift, no blend");
    }

    function test_the_blend_box_is_the_pill_plus_the_lift_plus_the_spill_along_the_band() {
        // The shader's box, from the pill's: the pill, the lift down to the
        // band (the pill's REST outward edge), and the blend's own reach
        // along the band on both flanks, where the fillets spill. Boxed, not
        // anchored (the turn is a size). The band's edge comes back in the
        // box's own frame, so the shader has one number for it.
        const pill = { x: 100, y: 5, width: 400, height: 60 };
        compare(Geometry.blendBox("bottom", pill, 4, 20), { x: 80, y: 5, width: 440, height: 64, bandEdge: 64, normal: { x: 0, y: 1 } });
        compare(Geometry.blendBox("top", pill, 4, 20), { x: 80, y: 1, width: 440, height: 64, bandEdge: 4, normal: { x: 0, y: -1 } });
        const side = { x: 5, y: 100, width: 60, height: 400 };
        compare(Geometry.blendBox("left", side, 4, 20), { x: 1, y: 80, width: 64, height: 440, bandEdge: 4, normal: { x: -1, y: 0 } });
        compare(Geometry.blendBox("right", side, 4, 20), { x: 5, y: 80, width: 64, height: 440, bandEdge: 64, normal: { x: 1, y: 0 } });
    }

    function test_the_pills_field_reaches_into_the_band_until_the_lift_clears_a_pixel() {
        // The blend is nothing at rest, so for the first pixel of a lift it
        // cannot bridge even the sub-pixel gap the coverage ramp exposes as
        // a hairline (measured). The pill's FIELD therefore reaches into the
        // band by a pixel less the lift - the union is seamless until the
        // blend is big enough to take over, and by then the reach is gone,
        // so the field's pill is the Rectangle's pill at the hand-over past
        // the pinch.
        // Two pixels of reach: the band's field edge sits a ramp inside the
        // band, so one pixel left the first frames a ramp short.
        const pill = { x: 100, y: 5, width: 400, height: 60 };
        compare(Geometry.FIELD_REACH, 2);
        compare(Geometry.fieldPill("bottom", pill, 0), { x: 100, y: 5, width: 400, height: 62 });
        compare(Geometry.fieldPill("bottom", pill, 0.25), { x: 100, y: 5, width: 400, height: 61.75 });
        compare(Geometry.fieldPill("bottom", pill, 2), pill, "two pixels up, nothing to reach");
        compare(Geometry.fieldPill("bottom", pill, 4), pill);
        compare(Geometry.fieldPill("top", pill, 0), { x: 100, y: 3, width: 400, height: 62 });
        const side = { x: 5, y: 100, width: 60, height: 400 };
        compare(Geometry.fieldPill("left", side, 0), { x: 3, y: 100, width: 62, height: 400 });
        compare(Geometry.fieldPill("right", side, 0.5), { x: 5, y: 100, width: 61.5, height: 400 });
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
