// Personas: a way of answering, saved whole - the fold.
//
// A persona bundles the system prompt with the settings that make an answer
// look the way somebody wanted it (temperature, at least). Built-ins ship in
// AiPersonas.qml; a user persona (config `ai.personas`) with the same id
// SHADOWS the built-in, and deleting the user copy brings the built-in back.
// Pure functions over plain rows; the singleton owns nothing but plumbing.
.pragma library

// User rows win by id; order: built-ins first (their order), then user-only.
function resolved(builtIns, userRows) {
    var users = (userRows || []).filter(function (p) {
        return p && typeof p.id === "string" && p.id.length > 0;
    });
    var byId = {};
    users.forEach(function (p) { byId[p.id] = p; });
    var out = (builtIns || []).map(function (p) { return byId[p.id] || p; });
    var builtinIds = {};
    (builtIns || []).forEach(function (p) { builtinIds[p.id] = true; });
    users.forEach(function (p) { if (!builtinIds[p.id]) out.push(p); });
    return out;
}

function personaById(list, id) {
    if (!id) return null;
    for (var i = 0; i < (list || []).length; i++)
        if (list[i].id === id) return list[i];
    return null;
}

// The prompt the request should carry: the persona's when one is active,
// the free-text prompt otherwise. "" id means custom.
function effectivePrompt(persona, customPrompt) {
    if (persona && typeof persona.systemPrompt === "string" && persona.systemPrompt.length > 0)
        return persona.systemPrompt;
    return customPrompt || "";
}
