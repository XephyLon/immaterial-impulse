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

function isVertical(edge) {
    return edge === "left" || edge === "right";
}

function normalizedEdge(edge) {
    return EDGES.indexOf(edge) === -1 ? "bottom" : edge;
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

// The same pair mapped onto the anchor names an Item actually uses, so a
// caller writes `anchors.topMargin: Geometry.margins(edge, ...).top` and the
// flip costs nothing.
function margins(edge, elevationMargin, gapsOut) {
    var e = normalizedEdge(edge);
    var pair = insets(elevationMargin, gapsOut);
    if (e === "bottom") return { top: pair.inward, bottom: pair.outward, left: 0, right: 0 };
    if (e === "top") return { top: pair.outward, bottom: pair.inward, left: 0, right: 0 };
    if (e === "left") return { left: pair.outward, right: pair.inward, top: 0, bottom: 0 };
    return { left: pair.inward, right: pair.outward, top: 0, bottom: 0 };
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
    var e = normalizedEdge(edge);
    if (e === "bottom") return "top";
    if (e === "top") return "bottom";
    if (e === "left") return "right";
    return "left";
}

// The sign the reveal travels in: a bottom dock hides DOWNWARD (positive y),
// a top dock upward. Callers animate one number and multiply.
function hideDirection(edge) {
    var e = normalizedEdge(edge);
    if (e === "bottom" || e === "right") return 1;
    return -1;
}
