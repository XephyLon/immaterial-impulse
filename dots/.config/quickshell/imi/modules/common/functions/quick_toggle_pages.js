.pragma library

.import "quick_toggle_layout.js" as Layout
.import "layout_ops.js" as LayoutOps

// The quick-toggle grid's PAGES (spec 2026-08-31): a list of pages, each a
// list of {type, size} entries, stored at
// Config.options.sidebar.quickToggles.android.pages.
//
// Everything here is COPY-ON-WRITE, which is not a style choice: the store
// is a nested list<var>, and mutating an inner array in place never
// notifies the outer `pages` property - the panel's signature would go
// stale and the grid would not follow the edit. The flat list's
// mutate-in-place spelling (26b625905) measured a FLAT list<var>; it does
// not carry over. Every editor builds a new pages value and assigns it.
//
// Delegates still survive edits: ids are stable and StableQuickToggleModel
// diffs, so a reassigned list that reorders one entry still syncs as a
// `move`.

function _isList(value) {
    // Not a typeof-array shortcut: a STRING also has a numeric length, and a
    // "junk" page would otherwise pass and land as an empty page.
    return !!value && typeof value !== "string" && typeof value.length === "number";
}

// One page's entries, cleaned: malformed entries dropped, sizes normalised
// through the layout lib's one normaliser, and any type already seen (on an
// earlier page, or earlier in this one) dropped - one home per toggle,
// first occurrence wins, the same spirit as quick_toggle_layout.idFor.
function _entries(rawList, seen) {
    var out = [];
    if (!_isList(rawList)) return out;
    for (var i = 0; i < rawList.length; i++) {
        var raw = rawList[i];
        if (!raw || typeof raw.type !== "string" || raw.type.length === 0) continue;
        if (seen[raw.type]) continue;
        seen[raw.type] = true;
        out.push({ type: raw.type, size: Layout.sizeOf(raw) });
    }
    return out;
}

// The one reader of the store. The stored `pages` when it holds any list at
// all, else the legacy flat `toggles` wrapped as one page; never fewer than
// one page, so the pager always has a current page to stand on.
function normalise(pagesRaw, legacyToggles) {
    var seen = {};
    var pages = [];
    if (_isList(pagesRaw)) {
        for (var i = 0; i < pagesRaw.length; i++) {
            if (_isList(pagesRaw[i])) pages.push(_entries(pagesRaw[i], seen));
        }
    }
    if (pages.length === 0) {
        var legacy = _entries(legacyToggles, seen);
        return legacy.length > 0 ? [legacy] : [[]];
    }
    return pages;
}

// Plain new arrays and objects, so what lands in Config is JSON-clean and
// no editor below can alias the store it is replacing.
function _copy(pages) {
    return (pages || []).map(function (page) {
        return (page || []).map(function (entry) {
            return { type: entry.type, size: entry.size };
        });
    });
}

function withAddedPage(pages) {
    var next = _copy(pages);
    next.push([]);
    return next;
}

// Edit-mode exit sweeps the blanks; at least one page always remains.
function pruned(pages) {
    var next = _copy(pages).filter(function (page) { return page.length > 0; });
    return next.length > 0 ? next : [[]];
}

function clampPage(pages, current) {
    var last = (pages ? pages.length : 1) - 1;
    return Math.max(0, Math.min(typeof current === "number" ? current : 0, last));
}

function usedTypes(pages) {
    var used = {};
    for (var i = 0; i < (pages ? pages.length : 0); i++)
        for (var j = 0; j < pages[i].length; j++)
            used[pages[i][j].type] = true;
    return used;
}

// A same-page move is layout_ops' move (the drag semantics that module
// exists to keep singular); a cross-page move splices out of one page and
// inserts into the other at an INSERTION index (0..length, clamped).
function withMove(pages, fromPage, fromIndex, toPage, toIndex) {
    var next = _copy(pages);
    if (fromPage < 0 || fromPage >= next.length) return next;
    if (toPage < 0 || toPage >= next.length) return next;
    if (fromPage === toPage) {
        next[fromPage] = LayoutOps.move(next[fromPage], fromIndex, toIndex);
        return next;
    }
    if (fromIndex < 0 || fromIndex >= next[fromPage].length) return next;
    var entry = next[fromPage].splice(fromIndex, 1)[0];
    var at = Math.max(0, Math.min(typeof toIndex === "number" ? toIndex : 0,
        next[toPage].length));
    next[toPage].splice(at, 0, entry);
    return next;
}

// A second home is refused rather than deduped later: the unused shelf is
// derived from usedTypes, so a type already placed is never offered - this
// guard is for the hand-written call.
function withInsert(pages, pageIndex, entry) {
    var next = _copy(pages);
    if (pageIndex < 0 || pageIndex >= next.length) return next;
    if (!entry || typeof entry.type !== "string") return next;
    if (usedTypes(next)[entry.type]) return next;
    next[pageIndex].push({ type: entry.type, size: Layout.sizeOf(entry) });
    return next;
}

function withRemove(pages, pageIndex, index) {
    var next = _copy(pages);
    if (pageIndex < 0 || pageIndex >= next.length) return next;
    next[pageIndex] = LayoutOps.remove(next[pageIndex], index);
    return next;
}

function withResize(pages, pageIndex, index, size) {
    var next = _copy(pages);
    if (pageIndex < 0 || pageIndex >= next.length) return next;
    if (index < 0 || index >= next[pageIndex].length) return next;
    next[pageIndex][index].size = size;
    return next;
}

// One string over every page, "|"-joined per-page layout signatures: it
// changes exactly when some page's sync would do something, or when the
// page split itself changes - the same observe-generously trick the flat
// panel used, extended over the nesting the store cannot notify through.
function signatureOf(pages, columns) {
    return (pages || []).map(function (page) {
        return Layout.signatureOf(page, columns);
    }).join("|");
}
