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

// What a floating dock reserves beyond an attached one: the lift. The surface
// no longer moves for the switch, so the zone is what keeps windows a gap
// away from the floating pill, as the moved surface used to. Bound to the
// CONFIGURED state, never to the animated scalar: the zone is a compositor
// re-arrange, written once at the start of a direction to the destination's
// value, and tiled windows travel on the compositor's own animation.
function splitZoneExtra(frameOn, attached, gapsOut) {
    if (!frameOn || attached) return 0;
    return Number(gapsOut) || 0;
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
// pill resting on a line), 1 is the free pill, between is the outward pair
// rounding with the scalar while the inward pair never moves. Clamped: the
// scalar's curve may leave the unit box, and a negative radius is not a
// corner.
function cornerRadiiAt(edge, radius, apart) {
    var a = Math.max(0, Math.min(1, Number(apart) || 0));
    var r = { topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius };
    var out = outwardSide(edge);
    var seam = radius * a;
    if (out === "bottom") { r.bottomLeft = seam; r.bottomRight = seam; }
    else if (out === "top") { r.topLeft = seam; r.topRight = seam; }
    else if (out === "left") { r.topLeft = seam; r.bottomLeft = seam; }
    else { r.topRight = seam; r.bottomRight = seam; }
    return r;
}

// The two ends of cornerRadiiAt, for a caller with no scalar.
function cornerRadii(edge, radius, attached) {
    return cornerRadiiAt(edge, radius, attached ? 0 : 1);
}

// How far apart the two outlines may be and still be bridged by a neck: the
// reference's 40% of the travelling body's thickness
// (Appearance.animation.splitNeckReach), or the whole travel when that is
// shorter - a 5 px lift on a 60 px pill is bridged all the way and the neck
// breaks at rest. No travel, no neck.
function neckReach(thickness, travel, fraction) {
    var t = Number(travel) || 0;
    if (t <= 0) return 0;
    return Math.min((Number(thickness) || 0) * (Number(fraction) || 0), t);
}

// The neck's waist: the pill's full width when the outlines touch, nothing
// at the reach, linear between.
function neckWaist(width, gap, reach) {
    var r = Number(reach) || 0;
    if (r <= 0) return 0;
    var g = Number(gap) || 0;
    return (Number(width) || 0) * Math.max(0, 1 - g / r);
}

// The neck's box, from the pill's: it fills the lift between the pill's
// outward edge and the band (the pill's REST outward edge, since the pill
// moved and the band did not), centred along the strip at the waist's width.
function neckBox(edge, pill, lift, waist) {
    var e = normalizedEdge(edge);
    var l = Number(lift) || 0;
    var w = Number(waist) || 0;
    if (isVertical(e)) {
        var y = pill.y + (pill.height - w) / 2;
        return e === "left"
            ? { x: pill.x - l, y: y, width: l, height: w }
            : { x: pill.x + pill.width, y: y, width: l, height: w };
    }
    var x = pill.x + (pill.width - w) / 2;
    return e === "top"
        ? { x: x, y: pill.y - l, width: w, height: l }
        : { x: x, y: pill.y + pill.height, width: w, height: l };
}

// The neck's two flanks are concave fillets (RoundCorner) whose straight
// edges hug the band and the waist. Named by the corner of its own box the
// fillet fills, for the start (left/top) and end (right/bottom) flank along
// the strip.
function neckFilletCorners(edge) {
    switch (normalizedEdge(edge)) {
    case "top": return { start: "topRight", end: "topLeft" };
    case "left": return { start: "bottomLeft", end: "topLeft" };
    case "right": return { start: "bottomRight", end: "topRight" };
    default: return { start: "bottomRight", end: "bottomLeft" };
    }
}

// Where each flank fillet's box sits, in the neck's own frame: against the
// band (the neck's far side, which is where the lift is measured to) and
// just outside the waist, at the start and the end of the strip.
function neckFilletOffsets(edge, neckWidth, neckHeight, size) {
    var e = normalizedEdge(edge);
    var sz = Number(size) || 0;
    var w = Number(neckWidth) || 0;
    var h = Number(neckHeight) || 0;
    if (isVertical(e)) {
        var x = e === "left" ? 0 : w - sz;
        return { start: { x: x, y: -sz }, end: { x: x, y: h } };
    }
    var y = e === "top" ? 0 : h - sz;
    return { start: { x: -sz, y: y }, end: { x: w, y: y } };
}

// A flank fillet is as tall as the neck and never wider than the room the
// waist leaves on its side of the pill.
function neckFilletSize(lift, pillWidth, waist) {
    var flank = ((Number(pillWidth) || 0) - (Number(waist) || 0)) / 2;
    return Math.max(0, Math.min(Number(lift) || 0, flank));
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
