.pragma library

// The arithmetic of an elastic resize.
//
// The model (docs/superpowers/specs/2026-08-11-expressive-morphing-design.md
// §3d): the card holds its size while pull builds, the edges being pulled
// distort first, and only past a breakaway threshold does the material give
// and the widget spring to the next offered span. Leftover pull carries, so
// one long drag walks through several spans without a re-grab.
//
// Pure by design: the grip handler feeds pointer deltas in and binds the
// results out, and everything below is scored by tests rather than by eye.
// The constants were tuned on screen against the design brief's live demo and
// are data, not preferences - change them here and nowhere else.

var BREAK_PX = 60;        // pull before the card gives
var BOW_PX = 14;          // how far an edge distorts at full tension
var BOW_EASE = 1.15;      // >1: resists, then gives - force must be built
var BULGE_PEAK = 0.85;    // the bulge sits near the corner being pulled
var CORNER_FOLLOW = 1.0;  // the dragged corner leads; the edges follow it
var SHARPEN = 0.5;        // pulled corner tightens, its neighbours open up

// ---- breakaway -----------------------------------------------------------

// How many spans a pull is worth, and what is left of it afterwards.
//
// Whole breakaways convert to steps; the remainder stays as live tension so
// the bow does not snap to zero the instant a span commits. Sign carries
// direction.
function giveAxis(pull, breakPx) {
    var limit = breakPx > 0 ? breakPx : BREAK_PX;
    var steps = Math.trunc(pull / limit);
    return { steps: steps, remainder: pull - steps * limit };
}

// The offered size one step along an axis, or the current one at a wall.
//
// `offered` is the manifest's list of {cols, rows}. A cols-step keeps the row
// count when it can (2x1 -> 3x1, not 2x1 -> 3x2) and otherwise takes the
// nearest row count among candidates; a rows-step mirrors that. Returns the
// CURRENT size when no offered size lies in the pulled direction - the wall
// the remaining tension rubber-bands against.
function stepSize(offered, current, dCols, dRows) {
    if (!offered || offered.length === 0 || !current) return current;
    var best = null;
    var bestPreferred = false;
    var bestDistance = Infinity;
    for (var i = 0; i < offered.length; i++) {
        var candidate = offered[i];
        if (dCols > 0 && candidate.cols <= current.cols) continue;
        if (dCols < 0 && candidate.cols >= current.cols) continue;
        if (dRows > 0 && candidate.rows <= current.rows) continue;
        if (dRows < 0 && candidate.rows >= current.rows) continue;
        // Preferred: the off-axis count survives the step (2x1 -> 3x1 on a
        // cols pull, not 2x1 -> 3x2). A preferred candidate always beats a
        // non-preferred one; ties resolve to the smallest step.
        var preferred = dCols !== 0
            ? candidate.rows === current.rows
            : candidate.cols === current.cols;
        var distance = dCols !== 0
            ? Math.abs(candidate.cols - current.cols)
            : Math.abs(candidate.rows - current.rows);
        if (best === null
                || (preferred && !bestPreferred)
                || (preferred === bestPreferred && distance < bestDistance)) {
            best = candidate;
            bestPreferred = preferred;
            bestDistance = distance;
        }
    }
    return best ?? current;
}

// ---- the bow -------------------------------------------------------------

// Edge distortion for a given pull. Sign-preserving power curve: at
// BOW_EASE > 1 the edge barely moves under a light pull and gives increasingly
// as the pull approaches the breakaway - force has to be built.
function bow(pull, breakPx, bowPx, ease) {
    var limit = breakPx > 0 ? breakPx : BREAK_PX;
    var reach = bowPx !== undefined ? bowPx : BOW_PX;
    var exponent = ease !== undefined ? ease : BOW_EASE;
    var t = Math.max(-1, Math.min(1, pull / limit));
    return Math.sign(t) * Math.pow(Math.abs(t), exponent) * reach;
}

// ---- corners under load --------------------------------------------------

// The corner radii of a card whose bottom-right corner is being pulled.
// Fixed radii are what read as "a rectangle with bent sides": under load the
// pulled corner tightens (material drawn toward a point), the two corners it
// pulls away from open up, and the anchored corner keeps its rest radius.
function cornerRadii(cap, bowX, bowY, bowPx, sharpen) {
    var reach = bowPx !== undefined ? bowPx : BOW_PX;
    var grip = sharpen !== undefined ? sharpen : SHARPEN;
    var tx = reach > 0 ? Math.max(-1, Math.min(1, bowX / reach)) : 0;
    var ty = reach > 0 ? Math.max(-1, Math.min(1, bowY / reach)) : 0;
    var load = Math.min(1, Math.hypot(tx, ty));
    return {
        tl: cap,
        tr: cap * (1 + grip * 0.5 * Math.abs(ty)),
        br: Math.max(2, cap * (1 - grip * load)),
        bl: cap * (1 + grip * 0.5 * Math.abs(tx))
    };
}

// ---- the outline ---------------------------------------------------------

// The bulged rounded rectangle, as segments a Canvas can draw and a test can
// chain-check. Every corner is rounded - the first version of this shape (in
// the design brief's demo) ended two edges on a bare point and the corner
// became a spike. The dragged corner travels CORNER_FOLLOW of the bulge; the
// bulge peak sits BULGE_PEAK of the way toward it.
//
// Returns { segments: [...] } where each segment is
//   { op: "move"|"line", x, y }  or  { op: "quad", cx, cy, x, y }.
function outline(w, h, bowX, bowY, radii, peak, follow) {
    var p = peak !== undefined ? peak : BULGE_PEAK;
    var f = follow !== undefined ? follow : CORNER_FOLLOW;
    var rTL = Math.min(radii.tl, w / 2, h / 2);
    var rTR = Math.min(radii.tr, w / 2, h / 2);
    var rBR = Math.min(radii.br, w / 2, h / 2);
    var rBL = Math.min(radii.bl, w / 2, h / 2);
    var cx = w + bowX * f;
    var cy = h + bowY * f;
    var midY = rTR + ((cy - rBR) - rTR) * p;
    var midX = rBL + ((cx - rBR) - rBL) * p;
    return { segments: [
        { op: "move", x: rTL, y: 0 },
        { op: "line", x: w - rTR, y: 0 },
        { op: "quad", cx: w, cy: 0, x: w, y: rTR },
        { op: "quad", cx: w + bowX, cy: midY, x: cx, y: cy - rBR },
        { op: "quad", cx: cx, cy: cy, x: cx - rBR, y: cy },
        { op: "quad", cx: midX, cy: h + bowY, x: rBL, y: h },
        { op: "quad", cx: 0, cy: h, x: 0, y: h - rBL },
        { op: "line", x: 0, y: rTL },
        { op: "quad", cx: 0, cy: 0, x: rTL, y: 0 }
    ] };
}
