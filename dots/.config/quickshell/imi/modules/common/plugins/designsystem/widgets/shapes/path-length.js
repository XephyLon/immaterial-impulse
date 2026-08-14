.pragma library

// Arc length along a run of cubic Beziers, so a partial stroke can be dashed
// onto a shape's *own* outline instead of drawn as a separate track beside it.
//
// A rounded polygon is a closed run of cubics (rounded-polygon.js), and a cubic
// has no closed-form length - so each one is sampled into a polyline. The
// estimate converges on the true length from below as `samples` rises, and 16
// segments is exact to far under a pixel here because a rounded polygon's
// cubics are short arcs rather than long S-curves.
//
// The cost is per geometry change, not per frame: a static shape pays it once,
// which is what makes a progress ring stroked around a cookie's outline cost
// nothing to animate. It lives beside rounded-polygon.js rather than inside the
// one component that strokes today, because the breathing cookie walks the
// same kind of path and a layout wanting both is a change of caller, not of
// maths.

var DEFAULT_SAMPLES = 16;

// Deliberately not cubic.js's `pointOnCurve`: a caller measuring cubics it
// built by hand should not have to construct that type, and the eight
// coordinates are the whole of what a length needs.
function pointOnCubic(cubic, t) {
    const u = 1 - t;
    return {
        x: cubic.anchor0X * u * u * u
            + cubic.control0X * 3 * t * u * u
            + cubic.control1X * 3 * t * t * u
            + cubic.anchor1X * t * t * t,
        y: cubic.anchor0Y * u * u * u
            + cubic.control0Y * 3 * t * u * u
            + cubic.control1Y * 3 * t * t * u
            + cubic.anchor1Y * t * t * t
    };
}

function cubicLength(cubic, samples) {
    if (!cubic)
        return 0;
    const steps = Math.max(1, Math.round(samples > 0 ? samples : DEFAULT_SAMPLES));
    let length = 0;
    let previous = { x: cubic.anchor0X, y: cubic.anchor0Y };
    for (let step = 1; step <= steps; step++) {
        const point = pointOnCubic(cubic, step / steps);
        length += Math.hypot(point.x - previous.x, point.y - previous.y);
        previous = point;
    }
    return isFinite(length) ? length : 0;
}

// `lengths[i]` is the distance from the path's start to the start of cubic `i`,
// so `lengths` is one longer than `cubics` and its last entry is `total`. The
// cumulative form is what a caller needs to find a point at a given progress;
// dashing only needs the total, and gets it from the same pass.
function measureCubics(cubics, samples) {
    const count = cubics && typeof cubics.length === "number" ? cubics.length : 0;
    const lengths = [0];
    let total = 0;
    for (let i = 0; i < count; i++) {
        total += cubicLength(cubics[i], samples);
        lengths.push(total);
    }
    return { total: total, lengths: lengths };
}

// The dash pattern that strokes the first `progress` of a closed path and
// nothing after it: one "on" run of that length, then an "off" run long enough
// to reach the end at any progress.
//
// Progress outside 0..1 is clamped rather than trusted - a player reporting a
// position past its own length is ordinary, and a negative dash length is not a
// pattern. A caller must skip the stroke entirely at zero: the pattern is
// honestly `[0, total]` there, and a zero-length dash is a degenerate thing to
// hand a painter.
function dashForProgress(total, progress) {
    const length = isFinite(total) && total > 0 ? total : 0;
    const fraction = isFinite(progress) ? Math.max(0, Math.min(1, progress)) : 0;
    return [length * fraction, length];
}

// The same pattern in the units a QML `Canvas` actually reads.
//
// HTML's `setLineDash` takes path-length units. Qt's implementation of it does
// not: it hands the array to `QPen::setDashPattern`, which is specified in
// multiples of the pen width. Handing it path units therefore produces a
// pattern the wrong size by a factor of the line width - and because the "off"
// run shrinks by the same factor, the pattern *repeats*, so a progress ring
// comes out as a ring of evenly spaced dashes that all grow together as
// progress rises. It looks like a deliberate dashed border rather than like a
// bug, which is why it needs naming rather than a comment at the call site.
function dashInPenWidths(total, progress, lineWidth) {
    const width = isFinite(lineWidth) && lineWidth > 0 ? lineWidth : 1;
    return dashForProgress(total, progress).map(value => value / width);
}
