.pragma library

// The sessions system's arithmetic (spec 2026-08-31): everything here is a
// pure function over plain rows, so the decisions - titles, order, edits,
// legacy mapping, index rebuild - are testable without a scene, and the
// AiSessions service above owns only files and debounce.
//
// An index ROW is { id, title, createdAt, updatedAt, pinned }.

var TITLE_MAX = 40;

// The first prompt, made a title: whitespace collapsed, capped with an
// ellipsis so the row never wraps. Empty in, empty out - the CALLER
// decides whether an empty title mints anything.
function titleFrom(prompt) {
    var clean = String(prompt || "").replace(/\s+/g, " ").trim();
    if (clean.length <= TITLE_MAX) return clean;
    return clean.slice(0, TITLE_MAX) + "…";
}

// Pinned first, then most recently touched. Copy, never in place.
function sortedIndex(rows) {
    return (rows || []).slice().sort(function (a, b) {
        if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1;
        return (b.updatedAt || 0) - (a.updatedAt || 0);
    });
}

// "now", "5m", "3h", "2d" - the row's whole vocabulary. Times are ms.
function agoLabel(nowMs, thenMs) {
    var s = Math.max(0, Math.floor((nowMs - thenMs) / 1000));
    if (s < 60) return "now";
    if (s < 3600) return Math.floor(s / 60) + "m";
    if (s < 86400) return Math.floor(s / 3600) + "h";
    return Math.floor(s / 86400) + "d";
}

function _copyRows(rows) {
    return (rows || []).map(function (row) {
        return { id: row.id, title: row.title, createdAt: row.createdAt,
                 updatedAt: row.updatedAt, pinned: !!row.pinned };
    });
}

function applyRename(rows, id, title) {
    return _copyRows(rows).map(function (row) {
        if (row.id === id) row.title = title;
        return row;
    });
}

function applyPin(rows, id, pinned) {
    return _copyRows(rows).map(function (row) {
        if (row.id === id) row.pinned = !!pinned;
        return row;
    });
}

function applyRemove(rows, id) {
    return _copyRows(rows).filter(function (row) { return row.id !== id; });
}

// A flush's index update: bump the row, or insert it for a session the
// index has never seen (the mint, or a rebuilt file). Title only ever
// grows less empty - a flush without one keeps what stands.
function applyTouch(rows, id, title, nowMs) {
    var next = _copyRows(rows);
    for (var i = 0; i < next.length; i++) {
        if (next[i].id !== id) continue;
        next[i].updatedAt = nowMs;
        if (title && title.length > 0) next[i].title = title;
        return next;
    }
    next.push({ id: id, title: title || "", createdAt: nowMs,
                updatedAt: nowMs, pinned: false });
    return next;
}

// A legacy flat chat file (a bare message array) as a session document.
// Titled from its first USER message - an answer is not a title.
function legacyToSession(messages, id, nowMs) {
    var list = (messages || []);
    var firstUser = "";
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].role === "user") {
            firstUser = list[i].rawContent || "";
            break;
        }
    }
    return {
        meta: { id: id, title: titleFrom(firstUser), createdAt: nowMs,
                updatedAt: nowMs, pinned: false },
        messages: list
    };
}

// The recovery fold: one meta JSON line per session file (jq -c '.meta'),
// corrupt lines dropped, result sorted. This is what makes the index a
// cache rather than a source of truth.
function rebuildIndex(metaLines) {
    var rows = [];
    for (var i = 0; i < (metaLines || []).length; i++) {
        try {
            var meta = JSON.parse(metaLines[i]);
            if (meta && typeof meta.id === "string" && meta.id.length > 0)
                rows.push({ id: meta.id, title: meta.title || "",
                            createdAt: meta.createdAt || 0,
                            updatedAt: meta.updatedAt || 0,
                            pinned: !!meta.pinned });
        } catch (e) { /* a corrupt meta is dropped, not fatal */ }
    }
    return sortedIndex(rows);
}

// A model's title reply, made safe for the index: models decorate -
// quotes, "Title:" prefixes, markdown, a trailing period, extra lines -
// and every decoration is stripped before the row shows it. An empty or
// unusable reply keeps the fallback (the trimmed first prompt).
function titleFromModelReply(raw, fallback) {
    var line = String(raw || "").split("\n").map(function (l) { return l.trim(); })
        .filter(function (l) { return l.length > 0; })[0] || "";
    line = line.replace(/^title\s*[:\-]\s*/i, "");
    line = line.replace(/^["'`\u201c\u2018*_#\s]+/, "").replace(/["'`\u201d\u2019*_\s]+$/, "");
    line = line.replace(/\.$/, "").replace(/\s+/g, " ").trim();
    if (line.length === 0) return fallback || "";
    if (line.length > TITLE_MAX) line = line.slice(0, TITLE_MAX) + "\u2026";
    return line;
}
