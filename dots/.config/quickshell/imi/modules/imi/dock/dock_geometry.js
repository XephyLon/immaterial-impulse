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

// Which side of its own surface the reveal push lands on. A dock anchors the
// body to its INWARD side and grows the margin there to shove it out: a
// bottom dock that pushed its bottomMargin would slide further onto the
// screen to hide.
function revealAnchorSide(edge) {
    return inwardSide(edge);
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
