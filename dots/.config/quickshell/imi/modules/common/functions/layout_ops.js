.pragma library

// Reordering a list by dragging one of its items, which four surfaces had each
// worked out for themselves: the bar's chip editor (LayoutSection), the dock
// strip (DragApps), the bar's copy of that strip (DocktoPanel) and the Android
// quick toggles (AndroidQuickToggleButton). Two questions between them - which
// slot is the pointer over, and what does the list look like afterwards - and
// four answers that did not agree on the second one.
//
// The disagreement is the reason this exists rather than the duplication.
// LayoutSection and DocktoPanel took the item out and put it back in at the
// drop index, so everything between the two positions shifted along by one;
// DragApps and the quick toggles exchanged the two entries, so a drag across
// three neighbours displaced exactly one of them and left the other two where
// they were. Both are defensible in isolation and only one of them is what a
// drag looks like, so a fifth copy would have been a coin toss - which is the
// shape AGENT.md's CavaService entry describes as two names for one thing
// letting one of them rot.
//
// Nothing here touches a store. A call site still owns where its list lives
// and when it is written back, because those genuinely differ: `Config.options`
// arrays, a `plugin-state.json` blob and a local drag order are three different
// commit paths and only the arithmetic between them is shared.

// The pointer is in scene coordinates and so are the centres; `axis` is "x" or
// "y" to compare along one of them, or null for a 2-D nearest.
//
// One axis is not an optimisation of two - it is the only thing that works in a
// column. Every slot in a vertical dock has the same x, so a 2-D comparison
// there degenerates into comparing a number with itself and the "nearest" slot
// is whichever the loop reached first: not a subtly wrong reorder, an inert one
// (8e608cb61 ("feat(dock): the dock strip lays out along whichever edge it is
// on")). The axis is chosen by the caller because only the caller knows which
// way its slots run.
//
// A hole in `centres` is skipped rather than treated as the origin. Callers
// have two reasons for one: a `Repeater` item that has not been created yet,
// and the dragged slot itself, which must not be its own nearest neighbour.
// Squared distance, because the comparison is all anyone wants and a square
// root is monotonic; ties go to the lower index, matching every loop this
// replaced.
function indexAt(centres, point, axis) {
    if (!centres || !point) return -1;
    var best = -1;
    var bestDistance = Infinity;
    for (var i = 0; i < centres.length; i++) {
        var centre = centres[i];
        if (!centre) continue;
        var distance;
        if (axis === "x" || axis === "y") {
            distance = Math.abs(point[axis] - centre[axis]);
        } else {
            var dx = point.x - centre.x;
            var dy = point.y - centre.y;
            distance = dx * dx + dy * dy;
        }
        if (distance < bestDistance) {
            bestDistance = distance;
            best = i;
        }
    }
    return best;
}

function isIndex(list, index) {
    return typeof index === "number" && index >= 0 && index < list.length;
}

// Take the item out and put it back at `to`, so it ends up at index `to` and
// everything it passed shifts one place the other way.
//
// This is the semantic difference the module exists for. Exchanging entries
// instead is identical for a step of one and wrong for anything longer: taking
// item 5 to position 2 has to leave 2, 3 and 4 in their own order one slot
// later, not fling 2 to the far end of the run. Dragging is a continuous
// gesture and a swap makes it discontinuous in the list.
//
// An index outside the list returns the list unchanged rather than a hole. A
// caller reads its indices off live `Repeater` items and a list that reflowed
// mid-gesture, so "no such slot" is reachable without anything being wrong.
function moveInPlace(list, from, to) {
    if (!list) return list;
    if (from === to) return list;
    if (!isIndex(list, from) || !isIndex(list, to)) return list;
    var item = list.splice(from, 1)[0];
    list.splice(to, 0, item);
    return list;
}

// The same reorder against a copy, for the call sites that hand a new list to
// whoever owns the store.
function move(list, from, to) {
    if (!list) return list;
    return moveInPlace(list.slice(), from, to);
}

// `moveInPlace` is not an optimisation of this and neither is a fallback for
// the other: the quick toggles deliberately mutate the live
// `Config.options.sidebar.quickToggles.android.toggles` array, because
// 26b625905 ("Revert \"fix(sidebar): make quick toggle edits actually notify\"
// and follow-ups") measured that every mutation form notifies and reverted the
// copy-and-reassign indirection that had been added on the belief that they do
// not. Both spellings run the same arithmetic here so that decision stays a
// decision about the store rather than a second reorder.

function insert(list, item, at) {
    if (!list) return list;
    var copy = list.slice();
    if (typeof at !== "number" || at < 0 || at > copy.length) return copy;
    copy.splice(at, 0, item);
    return copy;
}

function remove(list, at) {
    if (!list) return list;
    var copy = list.slice();
    if (!isIndex(copy, at)) return copy;
    copy.splice(at, 1);
    return copy;
}

// Which bucket a drop lands in, and where in it - for the bar's three layouts,
// which are separate lists laid out along one axis.
//
// `buckets` is an array of `{ centres, anchor }`: `centres` are the drawn
// slots' scene centres with the same holes `indexAt` takes (the dragged slot,
// a Repeater item not built yet), and `anchor` is a stand-in point for a
// bucket with nothing visible in it - an empty middleLayout has no slot
// centres at all, and without a stand-in it could never win a drop, which is
// exactly the "empty bucket must be a valid drop target" half of the bar's
// bucket boundaries. A bucket whose every slot is a hole is empty in the same
// sense: dragging the only widget of a bucket must leave that bucket
// droppable-back-into.
//
// The answer's `index` is an INSERTION index (0..length), not a nearest slot:
// the caller splices with it, and "past the last slot" has to be representable
// or nothing can be dropped at a bucket's end. Nearest is decided along the
// one axis the buckets run - the same reasoning as `indexAt`'s column note -
// and the near/far side of the winning centre decides before/after.
function dropTarget(buckets, point, axis) {
    if (!buckets || !point) return null;
    var best = null;
    var bestDistance = Infinity;
    for (var b = 0; b < buckets.length; b++) {
        var bucket = buckets[b];
        if (!bucket) continue;
        var centres = bucket.centres || [];
        var sawSlot = false;
        for (var i = 0; i < centres.length; i++) {
            var centre = centres[i];
            if (!centre) continue;
            sawSlot = true;
            var distance = Math.abs(point[axis] - centre[axis]);
            if (distance < bestDistance) {
                bestDistance = distance;
                best = { bucket: b, index: i + (point[axis] > centre[axis] ? 1 : 0) };
            }
        }
        if (!sawSlot && bucket.anchor) {
            var anchorDistance = Math.abs(point[axis] - bucket.anchor[axis]);
            if (anchorDistance < bestDistance) {
                bestDistance = anchorDistance;
                best = { bucket: b, index: 0 };
            }
        }
    }
    return best;
}

// The bar draws its layouts FILTERED - an empty tray drops sysTray, a disabled
// plugin drops its widget - so a drag's indices count VISIBLE slots while the
// store holds the whole list. `flags[i]` says whether stored entry i is drawn;
// these three walk between the two framings so a reorder shifts the hidden
// entries along with their visible neighbours instead of eating them.

// The stored index of the nth drawn entry, or -1 past the visible count.
function nthVisible(flags, n) {
    if (!flags) return -1;
    var seen = 0;
    for (var i = 0; i < flags.length; i++) {
        if (!flags[i]) continue;
        if (seen === n) return i;
        seen++;
    }
    return -1;
}

// A visible insertion index as a stored one: before the nth drawn entry, or at
// the stored end for an insertion at or past the visible count - an append
// stays an append whatever is hidden at the tail.
function insertionForVisible(flags, insertion) {
    var stored = nthVisible(flags, insertion);
    return stored === -1 ? (flags ? flags.length : 0) : stored;
}

// An insertion index counts a GAP and a move destination counts a SLOT: taking
// the dragged item out first shifts every gap past it one place down, so the
// two agree below the drag origin and differ by one above it. Named rather
// than spelled at the call site, because an off-by-one here reads as a reorder
// that "lands one short" only when the drag crosses more than one neighbour.
function moveTargetForInsertion(from, insertion) {
    return insertion > from ? insertion - 1 : insertion;
}
