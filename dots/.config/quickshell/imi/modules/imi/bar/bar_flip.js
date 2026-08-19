.pragma library

// FLIP (First, Last, Invert, Play) for a bar slot, as arithmetic.
//
// The rendering half cannot be tested - qmltestrunner builds no bar - so the
// decisions live here and BarGroup.qml owns only the transform and the parent
// walk. Same split as dock_geometry.js and layout_ops.js.
//
// Two things about the shape are load-bearing.
//
// The offset is INVERTED from a position the caller measured, never from a
// property that is being animated: a Behavior handed a target that moves every
// frame restarts every frame and never ticks (AGENT.md, b710ef731). What the
// caller animates is the translate this returns, toward zero, which nothing
// else writes.
//
// And the travel ACCUMULATES onto whatever translate is already in force, so a
// second reflow landing mid-flight retargets from where the slot is drawn
// rather than from where the layout has already put it. Two writes inside one
// layout pass telescope to `recorded - final` whatever order they arrive in,
// which is what makes the caller free to re-measure as often as it likes.

// Below this the reposition is not worth a frame of motion: a sub-pixel
// settle, or a slot the layout put back where it already was.
var MIN_TRAVEL = 1;

// FIRST/LAST: where a chain of ancestors puts an item, in the frame the walk
// stopped at.
//
// Deliberately a sum of x/y rather than `mapToItem`: that composes TRANSFORMS
// too, so a slot part-way through its own FLIP would report the position it is
// drawn at, and the next reposition would invert from a moving number - the
// feedback loop this whole module is arranged to avoid.
function chainOrigin(nodes) {
    var x = 0;
    var y = 0;
    var count = nodes && typeof nodes.length === "number" ? nodes.length : 0;
    for (var i = 0; i < count; i++) {
        var node = nodes[i];
        if (!node) continue;
        x += node.x;
        y += node.y;
    }
    return { x: x, y: y };
}

// INVERT: the offset that puts an item back where it was drawn.
function invert(recorded, current) {
    if (!recorded || !current) return { x: NaN, y: NaN };
    return { x: recorded.x - current.x, y: recorded.y - current.y };
}

// A bar runs along ONE axis, and only that axis is a reorder. The cross-axis
// term of a reposition is the bar changing thickness - every slot at once,
// which reads as the bar resizing rather than as its contents rearranging -
// so it is dropped rather than animated. (A comparison on the wrong axis of a
// turned layout is inert rather than wrong, which is the trap the dock's
// column reorder shipped with; naming the axis is how that is avoided.)
function alongAxis(offset, vertical) {
    if (!offset) return NaN;
    return vertical ? offset.y : offset.x;
}

// PLAY: the translate to animate from, and whether this reposition earns one.
//
// The floor is written as `!(|delta| >= min)` rather than `|delta| < min` so
// an absent record - which arrives as NaN, because a slot with nothing to
// invert from has no first position - refuses instead of comparing false and
// playing a jump from nowhere.
function repositionTravel(held, recorded, current, vertical, minTravel) {
    var delta = alongAxis(invert(recorded, current), vertical);
    if (!(Math.abs(delta) >= minTravel)) return { travel: held, play: false };
    return { travel: held + delta, play: true };
}
