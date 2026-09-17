.pragma library

// Where the dock sits, for each edge it can be put on.
//
// The dock spelled all of this out four times - in Dock.qml's anchors and
// exclusive zone, and again as hand-written topMargin/bottomMargin pairs in
// DockSeparator, DockButton and DockAppButton. Four coordinated edits that
// have to agree is how a mirror drifts; this is the one derivation they read.
//
// Two ideas carry the whole thing:
//
//   INWARD is toward the screen's middle, OUTWARD is toward the edge the dock
//   is on. The dock's margins are asymmetric - an elevation margin inward for
//   the drop shadow, the compositor's gap outward - and naming them by
//   direction rather than by "top" and "bottom" is what makes the flip a
//   state change instead of a rewrite.
//
//   THICKNESS is the dock's size across its own axis: a height at the top and
//   bottom edges, a width at the left and right ones. The arithmetic does not
//   change with the axis, only what it is applied to.

var EDGES = ["top", "bottom", "left", "right"];

// The only table in this file. INWARD and OUTWARD are the whole vocabulary,
// and every side name below is read out of here rather than spelled again -
// a popup's gravity, the reveal's anchor, the shadow margin and the hover
// lift's direction are all one relation asked four different ways.
var OPPOSITE = { top: "bottom", bottom: "top", left: "right", right: "left" };

function isVertical(edge) {
    return edge === "left" || edge === "right";
}

function normalizedEdge(edge) {
    return EDGES.indexOf(edge) === -1 ? "bottom" : edge;
}

// Toward the screen edge the dock is on. Which is the edge itself - named so
// a caller reads its intent rather than the coincidence.
function outwardSide(edge) {
    return normalizedEdge(edge);
}

// Toward the middle of the screen.
function inwardSide(edge) {
    return OPPOSITE[normalizedEdge(edge)];
}

// Which sides the layer surface anchors to: both ends of the long axis, plus
// the edge it lives on.
function anchors(edge) {
    var e = normalizedEdge(edge);
    if (isVertical(e))
        return { top: true, bottom: true, left: e === "left", right: e === "right" };
    return { left: true, right: true, top: e === "top", bottom: e === "bottom" };
}

// The dock's own size across its axis, including both margins. `dockHeight`
// keeps its name at every edge: it is the thickness, and renaming it would
// mean migrating every preset that has ever stored it.
function thickness(dockHeight, elevationMargin, gapsOut) {
    return dockHeight + elevationMargin + gapsOut;
}

// What the compositor reserves. Unchanged arithmetic, and deliberately
// expressed against the measured baseline: at defaults (height 60, elevation
// 10, gaps 5) the compositor reports reserved [0, 45, 0, 65] and a 5120x75
// dock, so a regression here is a number rather than an impression that
// something moved.
function exclusiveZone(dockHeight, elevationMargin, gapsOut) {
    return thickness(dockHeight, elevationMargin, gapsOut)
        - gapsOut - (elevationMargin - gapsOut);
}

// The margin pair, by direction rather than by side name.
function insets(elevationMargin, gapsOut) {
    return { inward: elevationMargin, outward: gapsOut };
}

// Any inward/outward pair mapped onto the four side names an Item actually
// uses for its anchors, margins and insets. Sides on the dock's LONG axis get
// zero: an inset there would eat into the strip rather than into its
// thickness, which is the mistake that reads as "the icons drifted".
//
// This is the one place a direction becomes a side name. A widget that spells
// out `topMargin` for the shadow and `bottomMargin` for the gap is correct at
// exactly one edge and silently wrong at the other three.
function directedSides(edge, inward, outward) {
    var sides = { top: 0, bottom: 0, left: 0, right: 0 };
    sides[inwardSide(edge)] = inward;
    sides[outwardSide(edge)] = outward;
    return sides;
}

// A margin or inset trio said in the dock's OWN axes. ACROSS the dock is the
// inward/outward pair above; ALONG it is the gap at both ends of the strip.
// §1's "written in terms of along and across rather than width and height",
// written once so a widget does not have to decide which of `topMargin` and
// `leftMargin` its number means this time.
function axisMargins(edge, inward, outward, along) {
    var sides = directedSides(edge, inward, outward);
    if (isVertical(edge)) {
        sides.top = along;
        sides.bottom = along;
    } else {
        sides.left = along;
        sides.right = along;
    }
    return sides;
}

// The dock body's own margin pair, mapped onto side names, so a caller writes
// `anchors.topMargin: Geometry.margins(edge, ...).top` and the flip costs
// nothing.
function margins(edge, elevationMargin, gapsOut) {
    var pair = insets(elevationMargin, gapsOut);
    return directedSides(edge, pair.inward, pair.outward);
}

// The box of anything that spans the dock's thickness and is sized by its
// content along the strip: the thickness ACROSS the dock's own axis, the
// item's own implicit size ALONG it.
//
// This exists so the turn is a change of SIZE. An item that anchors the two
// ends of its across axis and centres on the other has to change WHICH
// anchors it uses when the dock turns, and Qt refuses a set that is
// momentarily {left, right, horizontalCenter} instead of re-applying it once
// the third clears - the item keeps the anchors of both orientations and
// fills the whole surface. Handing the size over means the anchors can stay
// `centerIn: parent` at every edge, which is a membership that never changes.
function contentBox(edge, thickness, alongWidth, alongHeight) {
    return isVertical(edge)
        ? { width: thickness, height: alongHeight }
        : { width: alongWidth, height: thickness };
}

// How far the dock is pushed off-screen when hidden, and how far it peeks
// when the pointer is near. Both are the INWARD margin's value, so the reveal
// is one animated number at every edge.
//
// `revealed` is the resting position, `peeking` leaves a sliver the pointer
// can hit, `hidden` is one pixel past gone - a dock that stops exactly at the
// edge leaves a seam of itself lit.
function revealOffsets(dockThickness, hoverRegion) {
    return {
        revealed: 0,
        peeking: dockThickness - hoverRegion,
        hidden: dockThickness + 1
    };
}

// Which way a popup opens from a dock on this edge: away from the edge, or
// the menu opens into it and is clipped.
function popupGravity(edge) {
    return inwardSide(edge);
}

// A popup anchored to the dock's whole SURFACE rather than to one button -
// the window-preview popup - needs a corner and a direction, not one side. It
// attaches at the start of the dock's long axis on the inward side, and grows
// inward and along that axis.
//
// Side names rather than Quickshell's `Edges` flags: a `.pragma library` has
// no QML enums in scope, so the caller maps the names. It does not get to
// decide them.
function popupAnchorSides(edge) {
    var e = normalizedEdge(edge);
    var axisStart = isVertical(e) ? "top" : "left";
    var axisEnd = isVertical(e) ? "bottom" : "right";
    return { edges: [inwardSide(e), axisStart], gravity: [inwardSide(e), axisEnd] };
}

// How far the whole dock surface moves in from the screen edge in frame mode
// (services/FrameGeometry.qml). The pill sits `gapsOut` inside its surface;
// the frame's band owns that gap. The surface sits where the ATTACHED tab
// needs it: in by band minus gap (nothing at all when the band is the gap,
// which it is by default; a little OUT when the band is thinner than the
// gap - a negative layer-shell margin, the same device the dead-pixel
// workaround uses). Floating is not a second surface position: the pill
// lifts inside the surface by `splitTravel`, so the attached <-> floating
// switch never reconfigures the surface and can be drawn as a motion
// (docs/proposals/motion-split.md §6). The compositor adds a margin on the
// anchored edge to the exclusive zone on its own, so the reservation follows
// without a second number. Outside frame mode the dock is where it always was.
function frameOffset(frameOn, band, gapsOut) {
    if (!frameOn) return 0;
    var b = Number(band) || 0;
    var g = Number(gapsOut) || 0;
    return b - g;
}

// ---- the split (docs/proposals/motion-split.md §6) -------------------------
//
// The band is the island and the pill is the child. Attached is the joined
// state (the tab fused with the band), floating is the apart state (a gap
// above it), and the pill is the one body that travels: it lifts off the band
// by the compositor's gap - that IS the distance between "on the band" and "a
// gap above it", whatever the band's thickness - and sinks back onto it. One
// scalar drives a direction (Appearance.animation.split), 0 fused, 1 apart;
// everything below is arithmetic on that scalar, kept here so
// tests/tst_dock_geometry.qml can pin it.

// The lift: the gap, while the frame is on and the dock reserves its edge. An
// unpinned dock never reserves and never lifts - its hover sliver has to stay
// AT the screen edge (Dock.qml) - so at the default band it takes the look
// change alone.
function splitTravel(frameOn, reserves, gapsOut) {
    if (!frameOn || !reserves) return 0;
    return Number(gapsOut) || 0;
}

// What the dock reserves beyond the attached zone: the lift, while the pill
// is up OR asked to go up. The surface no longer moves for the switch, so
// the zone is what keeps windows a gap away from a floating pill, and it
// reserves the UNION of where the pill is and where it is going: it steps at
// the start of a lift (windows move away, the pill lifts into the space)
// and at the end of a landing (the pill lands, then the windows follow it
// in). Stepping at the start of a landing put the windows against the
// still-floating pill for the length of the motion. Two steps per gesture at
// most - a boolean that flips, never a per-frame write - and tiled windows
// travel on the compositor's own animation.
function splitZoneExtra(travel, apartTarget, progress) {
    var t = Number(travel) || 0;
    if (t <= 0) return 0;
    return (apartTarget || (Number(progress) || 0) > 0) ? t : 0;
}

// The pill lifts into its own inward elevation margin. A gap bigger than that
// margin would lift the pill out of its surface, so the dock grows across
// its axis by exactly the shortfall - nothing at the defaults (gap 5,
// elevation 10).
function splitRoom(gapsOut, elevationMargin) {
    var g = Number(gapsOut) || 0;
    var e = Number(elevationMargin) || 0;
    return Math.max(0, g - e);
}

// The pill's margin pair with a lift applied: outward grows by the lift,
// inward shrinks by it (and carries the room), so the sum is the box's
// thickness whatever the scalar says. `rest` is `margins()`'s answer.
function liftedMargins(edge, rest, room, lift) {
    var e = normalizedEdge(edge);
    var inward = (Number(rest[inwardSide(e)]) || 0) + (Number(room) || 0) - (Number(lift) || 0);
    var outward = (Number(rest[outwardSide(e)]) || 0) + (Number(lift) || 0);
    return directedSides(e, inward, outward);
}

// Where the icons go so they ride the pill: the strip is centred in the
// dock's box and the pill is not, once it has lifted (or the box has room),
// so the strip takes the difference as a centre offset along the across
// axis - inward by the lift, outward by half the room.
function liftOffset(edge, room, lift) {
    var along = (Number(room) || 0) / 2 - (Number(lift) || 0);
    var v = inwardVector(edge);
    return { x: -v.x * along, y: -v.y * along };
}

// Which of the pill's corners stay round, as a function of how far apart
// the pill and the band are: 0 is the fused tab (the outward pair squared -
// that seam is where the tab grows out of the band, and a rounded seam is a
// pill resting on a line), 1 is the free pill. The outward pair rounds over
// the NECK'S span - from `seam`, where the outlines part, to the pinch-off
// `reach` of the way through the settle - because the rounding is the
// seam's own shape opening: the neck's flank exposes the corner as it
// narrows, and a corner still square once exposed hovered over a lit gap
// (rounding to rest did that). The inward pair never moves. A look with no
// lift passes seam 0 and reach 1 and rounds over its whole scalar. Clamped:
// the scalar's curve may leave the unit box, and a negative radius is not a
// corner.
function cornerRadiiAt(edge, radius, apart, seam, reach) {
    var sm = Math.max(0, Math.min(0.999, Number(seam) || 0));
    var rc = Math.max(0.001, Math.min(1, reach === undefined ? 1 : (Number(reach) || 0)));
    var a = Math.max(0, Math.min(1, ((Number(apart) || 0) - sm) / ((1 - sm) * rc)));
    var r = { topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius };
    var out = outwardSide(edge);
    var rounded = radius * a;
    if (out === "bottom") { r.bottomLeft = rounded; r.bottomRight = rounded; }
    else if (out === "top") { r.topLeft = rounded; r.topRight = rounded; }
    else if (out === "left") { r.topLeft = rounded; r.bottomLeft = rounded; }
    else { r.topRight = rounded; r.bottomRight = rounded; }
    return r;
}

// The two ends of cornerRadiiAt, for a caller with no scalar.
function cornerRadii(edge, radius, attached) {
    return cornerRadiiAt(edge, radius, attached ? 0 : 1, 0, 1);
}

// The neck's waist on the scalar: the pill's full width up to the seam (the
// fused outline stretching - the reference's swell), narrowing to nothing at
// the pinch-off, which sits `reach` of the way through the settle half
// (Appearance.animation.splitNeckReach, set from the reference's 165 ms of
// neck in the time domain). Past the pinch there is no neck: the bodies
// settle APART.
function neckWaist(width, apart, seam, reach) {
    var rc = Number(reach) || 0;
    if (rc <= 0) return 0;
    var sm = Math.max(0, Math.min(0.999, Number(seam) || 0));
    var span = (1 - sm) * rc;
    var t = Math.max(0, Math.min(1, ((Number(apart) || 0) - sm) / span));
    return (Number(width) || 0) * (1 - t);
}

// The neck's box, from the pill's: it fills the lift between the pill's
// outward edge and the band (the pill's REST outward edge, since the pill
// moved and the band did not), centred along the strip at the waist plus a
// fillet on each flank - and it reaches NECK_OVERLAP into the pill. The pill
// is drawn over it, so nothing shows; without the overlap the pill and the
// neck each antialiased their half of a boundary sitting on a fractional
// pixel while the lift animated, and two half-coverages of one colour over
// the light band composited to a hairline across the whole width for the
// whole fused half of every lift (measured on the sandbox frames: a
// (71, 76, 74) row inside a (22, 21, 21) body).
var NECK_OVERLAP = 1;
function neckBox(edge, pill, lift, waist, fillet) {
    var e = normalizedEdge(edge);
    var l = (Number(lift) || 0) + NECK_OVERLAP;
    var w = (Number(waist) || 0) + 2 * (Number(fillet) || 0);
    if (isVertical(e)) {
        var y = pill.y + (pill.height - w) / 2;
        return e === "left"
            ? { x: pill.x - l + NECK_OVERLAP, y: y, width: l, height: w }
            : { x: pill.x + pill.width - NECK_OVERLAP, y: y, width: l, height: w };
    }
    var x = pill.x + (pill.width - w) / 2;
    return e === "top"
        ? { x: x, y: pill.y - l + NECK_OVERLAP, width: w, height: l }
        : { x: x, y: pill.y + pill.height - NECK_OVERLAP, width: w, height: l };
}

// A flank fillet is as tall as the neck and never wider than the room the
// waist leaves on its side of the pill.
function neckFilletSize(lift, pillWidth, waist) {
    var flank = ((Number(pillWidth) || 0) - (Number(waist) || 0)) / 2;
    return Math.max(0, Math.min(Number(lift) || 0, flank));
}

// The neck as ONE SVG path in its box's own frame - the waist rectangle with
// a concave fillet on each flank, its straight edges hugging the pill and
// the band - so it is one Shape with no layer rather than three items with
// two. Drawn in (along, across): along the strip, and across from the pill
// side (0) to the band (`lift` - the box's own depth, overlap included);
// each edge maps that figure into its box, and a
// reflection (top, right) flips the arcs' sweep where a rotation (left: two
// reflections) keeps it.
function neckPath(edge, waist, lift, fillet) {
    var e = normalizedEdge(edge);
    var w = Number(waist) || 0;
    var l = Number(lift) || 0;
    var f = Math.max(0, Math.min(Number(fillet) || 0, l));
    var flips = (e === "top" || e === "right") ? 1 : 0;
    function m(u, v) {
        switch (e) {
        case "top": return [u, l - v];
        case "right": return [v, u];
        case "left": return [l - v, u];
        default: return [u, v];
        }
    }
    function pt(cmd, u, v) { var p = m(u, v); return cmd + " " + p[0] + " " + p[1]; }
    function arc(u, v) { var p = m(u, v); return "A " + f + " " + f + " 0 0 " + flips + " " + p[0] + " " + p[1]; }
    function reach(u, v) { return f > 0 ? arc(u, v) : pt("L", u, v); }
    return [pt("M", f, 0), pt("L", f + w, 0), pt("L", f + w, l - f), reach(f + w + f, l),
            pt("L", 0, l), reach(f, l - f), "Z"].join(" ");
}

// A direction's duration from part way: the tier times the distance left,
// never under the floor (the effects tier). The source's rule
// (motion-split.md §1, `max(220, 820 * progress)`): a Behavior re-targeted
// mid-flight otherwise takes the whole tier to cover a tenth of the way, and
// a lift reversed at 1% would be a jump without the floor. Clamped to the
// unit box: the curve may overshoot, and a distance over 1 is a whole
// direction.
function splitDuration(base, floor, from, to) {
    var b = Number(base) || 0;
    var f = Number(floor) || 0;
    var d = Math.min(1, Math.abs((Number(to) || 0) - (Number(from) || 0)));
    return Math.max(f, Math.round(b * d));
}

// The blend's radius - the neck as a distance field (motion-split.md §1,
// §6): the smooth-minimum of the pill's field and the band's, whose radius
// is what bridges the two. It has to be ZERO at rest, since a blend against
// a fused tab fillets the tab's sides where the Rectangle that takes over
// draws none - a pop at the hand-over - and it grows to its full value at
// the seam, held through the settle where the waist does the narrowing. In
// LIFTS: a polynomial smooth-minimum bridges a gap of g once its radius
// passes 2g, and the gap at the seam is half the lift, so four lifts keeps
// the full waist bridged to the seam with room for the flanks.
var BLEND_LIFTS = 4;
// The field's coverage ramp, in pixels either side of the outline: a
// Rectangle's own antialiasing is about a pixel wide, and the hand-over
// between the two must not change the edge.
var BLEND_SOFTNESS = 0.75;
function neckBlend(travel, apart, seam) {
    var t = Number(travel) || 0;
    if (t <= 0) return 0;
    var sm = Math.max(0.001, Number(seam) || 0);
    var rise = Math.max(0, Math.min(1, (Number(apart) || 0) / sm));
    return BLEND_LIFTS * t * rise;
}

// The pill as the field sees it: reaching NECK_OVERLAP into the band, less
// the lift. The blend is nothing at rest, so for the first pixel of a lift
// it cannot bridge even the sub-pixel gap the coverage ramp exposes as a
// hairline (measured: a 51 on a 21 body along the whole seam); the reach
// keeps the union seamless until the blend is big enough to take over, and
// is gone by then, so past the pinch the field's pill is the Rectangle's.
function fieldPill(edge, pill, lift) {
    var e = normalizedEdge(edge);
    var r = Math.max(0, NECK_OVERLAP - (Number(lift) || 0));
    var box = { x: pill.x, y: pill.y, width: pill.width, height: pill.height };
    if (e === "bottom") box.height += r;
    else if (e === "top") { box.y -= r; box.height += r; }
    else if (e === "right") box.width += r;
    else { box.x -= r; box.width += r; }
    return box;
}

// The shader's box, from the pill's: the pill, the lift down to the band
// (the pill's REST outward edge, since the pill moved and the band did
// not), and the blend's reach along the band on both flanks, where the
// fillets spill. Boxed, never anchored. `bandEdge` is the band's inner edge
// in the box's own frame along the across axis, and `normal` points INTO
// the band, so the shader's field for the band is one half-plane.
function blendBox(edge, pill, lift, spill) {
    var e = normalizedEdge(edge);
    var l = Number(lift) || 0;
    var sp = Number(spill) || 0;
    if (isVertical(e)) {
        var box = { x: pill.x, y: pill.y - sp, width: pill.width + l, height: pill.height + 2 * sp };
        if (e === "left") { box.x = pill.x - l; box.bandEdge = l; box.normal = { x: -1, y: 0 }; }
        else { box.bandEdge = pill.width + l; box.normal = { x: 1, y: 0 }; }
        return box;
    }
    var box = { x: pill.x - sp, y: pill.y, width: pill.width + 2 * sp, height: pill.height + l };
    if (e === "top") { box.y = pill.y - l; box.bandEdge = l; box.normal = { x: 0, y: -1 }; }
    else { box.bandEdge = pill.height + l; box.normal = { x: 0, y: 1 }; }
    return box;
}

// The direction a dock icon lifts on hover and bounces on launch: inward, so
// the icon rises out of the dock rather than into the screen edge. One vector
// instead of four call sites each choosing an axis and a sign.
function inwardVector(edge) {
    var toward = inwardSide(edge);
    return {
        x: toward === "left" ? -1 : (toward === "right" ? 1 : 0),
        y: toward === "top" ? -1 : (toward === "bottom" ? 1 : 0)
    };
}

// The bar's edge, said in the dock's vocabulary. The bar stores a pair of
// booleans in which `bottom` stops meaning bottom and starts meaning RIGHT
// once `vertical` is set (VerticalBar.qml anchors left/right off it), and
// three files already re-derive a name from that pair.
//
// This is not a fourth copy of that for the bar's benefit. It exists so the
// dock's settings row can ask whether it is being sent to an edge an
// auto-hiding bar already owns, and a comparison between two vocabularies
// means nothing.
function barEdge(barVertical, barBottom) {
    if (!barVertical)
        return barBottom ? "bottom" : "top";
    return barBottom ? "right" : "left";
}

// The sign the reveal travels in: a bottom dock hides DOWNWARD (positive y),
// a top dock upward. Callers animate one number and multiply.
function hideDirection(edge) {
    var e = normalizedEdge(edge);
    if (e === "bottom" || e === "right") return 1;
    return -1;
}
