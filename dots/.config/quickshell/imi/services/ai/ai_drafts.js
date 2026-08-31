.pragma library

// Composer drafts as a fold over a plain map { sessionId|"": text } - ""
// is the not-yet-minted chat's slot. Empty text deletes: a cleared
// composer is not a draft.

function withDraft(map, key, text) {
    var next = {};
    for (var k in (map || {})) next[k] = map[k];
    var clean = String(text ?? "");
    if (clean.length === 0) delete next[String(key ?? "")];
    else next[String(key ?? "")] = clean;
    return next;
}

function draftFor(map, key) {
    return String((map || {})[String(key ?? "")] ?? "");
}

// Sessions get deleted; their drafts follow. The new-chat slot always
// survives - it belongs to no session.
function prune(map, validKeys) {
    var keep = {};
    var valid = validKeys || [];
    for (var k in (map || {})) {
        if (k === "" || valid.indexOf(k) !== -1) keep[k] = map[k];
    }
    return keep;
}
