.pragma library

// Widget-to-widget edge alignment (spec §6): the candidate set, the
// perpendicular relevance filter and the two-threshold hold, kept pure so the
// decisions are reachable from tst_edge_snap.qml. Nothing about the rendered
// guide is - the caller (AbstractWidget) collects the neighbour rects, feeds
// the drag's SHADOW position through resolveSnap on every event, and draws the
// guide wherever the held candidate says.
//
// The two thresholds are a Schmitt trigger: a guide is acquired close and
// released only farther away, and BOTH tests compare the unsnapped shadow
// position, never the rendered one. With one threshold, snapping puts the
// widget on the target while the pointer sits within it, so the next event
// re-snaps; pushing just past unsnaps to a position that may be within the
// threshold again from the other side - a per-event flip-flop, because the
// decision boundary and the resulting position are the same number. The gap
// between the two numbers is what makes the hold feel like a detent.

const ACQUIRE_PX = 18;
const RELEASE_PX = 32;

// A widget far across the axis being snapped offers no alignments: without
// this, a widget in one corner left-aligns to something in the opposite one,
// and the guide drawn between them is a screen-long line about nothing the
// user is arranging. Measured as the GAP between the two perpendicular
// extents - overlap is zero - and the boundary value is excluded: the limit
// is the first distance that contributes nothing.
const PERPENDICULAR_LIMIT_PX = 600;

function perpendicularGap(aPos, aSize, bPos, bSize) {
    return Math.max(bPos - (aPos + aSize), aPos - (bPos + bSize), 0);
}

// Four relations per neighbour per axis - near-to-near, far-to-far,
// near-to-far, far-to-near - each carrying TWO numbers: the `target` the
// dragged widget travels to and the `guide` the line is drawn at. They differ
// for two of the four, because the line belongs to the OTHER widget's edge:
// aligning our right edge to their right edge lands us at far - size, but the
// alignment the line shows is at far.
//
// The two ADJACENCY relations - sitting beside or below a neighbour - land one
// `gap` away from it, not flush. Flush was the first cut and it glued widgets
// into one slab; the gap that already separates the cells INSIDE a multi-cell
// widget (`Appearance.sizes.widgetGridGap`) is what makes two widgets side by
// side read as one continuous grid instead. The two ALIGNMENT relations take
// no gap: aligning our left edge to theirs is a line, not a distance. The
// guide is still drawn at the neighbour's own edge for all four - the line
// says what the widget aligned to; the gap is where the widget lands.
//
// `gap` is a parameter rather than a constant here so this module stays free
// of Appearance (it is read by tst_edge_snap.qml with no shell around it) and
// so a caller on a scaled canvas hands in the scaled value.
//
// `neighbours` is iterated by index and length rather than Array methods on
// purpose: a list that has crossed a QML model boundary keeps its indices and
// its length and loses its Array brand.
function candidatesForAxis(neighbours, axis, size, perpPos, perpSize, gap) {
    const isX = axis === "x";
    const spacing = gap || 0;
    const out = [];
    for (let i = 0; i < neighbours.length; i++) {
        const n = neighbours[i];
        const near = isX ? n.x : n.y;
        const far = near + (isX ? n.width : n.height);
        const nPerpPos = isX ? n.y : n.x;
        const nPerpSize = isX ? n.height : n.width;
        if (perpendicularGap(perpPos, perpSize, nPerpPos, nPerpSize)
                >= PERPENDICULAR_LIMIT_PX)
            continue;
        out.push({ target: near, guide: near });                  // near-to-near
        out.push({ target: far - size, guide: far });             // far-to-far
        out.push({ target: far + spacing, guide: far });          // near-to-far
        out.push({ target: near - size - spacing, guide: near }); // far-to-near
    }
    return out;
}

// One axis's snap decision for one event: the held candidate, or null.
//
// `shadowPos` is the drag proxy's position - where the widget WOULD be with no
// snap - and `held` is whatever this function answered last event. A held
// candidate keeps its hold while the shadow stays inside the release
// threshold AND the candidate is still in the regenerated list (a neighbour
// the perpendicular filter has since dropped releases immediately: a guide
// for a neighbour that no longer qualifies is a line about nothing). The
// match is by VALUE, not reference - the list is rebuilt every event.
function resolveSnap(shadowPos, candidates, held) {
    if (held) {
        for (let i = 0; i < candidates.length; i++) {
            const c = candidates[i];
            if (c.target === held.target && c.guide === held.guide) {
                if (Math.abs(shadowPos - c.target) < RELEASE_PX)
                    return c;
                break;
            }
        }
    }
    let best = null;
    let bestDistance = ACQUIRE_PX;
    for (let i = 0; i < candidates.length; i++) {
        const distance = Math.abs(shadowPos - candidates[i].target);
        if (distance < bestDistance) {
            best = candidates[i];
            bestDistance = distance;
        }
    }
    return best;
}
