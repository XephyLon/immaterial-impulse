// What the assistant is allowed to remember between conversations - the fold.
//
// Facts are plain rows {id, text, at, source}, newest last, deduplicated
// case-insensitively and capped; the block they become is prepended to the
// system prompt. Everything here copies; the singleton owns the file.
.pragma library

function withFact(facts, text, id, now, source, limit) {
    var value = String(text || "").trim();
    if (value.length === 0) return facts || [];
    var list = (facts || []);
    var lower = value.toLowerCase();
    for (var i = 0; i < list.length; i++)
        if (String(list[i].text).toLowerCase() === lower) return list;
    var out = list.concat([{ id: id, text: value, at: now, source: String(source || "user") }]);
    var cap = Math.max(1, limit || 40);
    return out.slice(-cap);
}

function withoutFact(facts, id) {
    return (facts || []).filter(function (f) { return String(f.id) !== String(id); });
}

function promptBlock(facts, enabled) {
    if (!enabled || !(facts || []).length) return "";
    var lines = facts.map(function (f) { return "- " + f.text; }).join("\n");
    return "## What you already know about this user\n" + lines;
}
