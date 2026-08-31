.pragma library

// Which fetched models SURFACE in the picker (spec 2026-08-31). One fold
// read by the picker filter and written by the browse toggles, so the two
// cannot disagree. An EMPTY selection surfaces everything: a small
// provider needs no ceremony, and curation is opt-in per provider.

function isSurfaced(selected, id) {
    var list = selected || [];
    if (list.length === 0) return true;
    return list.indexOf(id) !== -1;
}

function withToggled(selected, id) {
    var next = (selected || []).slice();
    var at = next.indexOf(id);
    if (at === -1) next.push(id);
    else next.splice(at, 1);
    return next;
}

// "custom_provider_2" -> 2; anything else -> -1. The key_id is the one
// marker every provider-fetched model already carries.
function providerIndexOf(keyId) {
    var match = /^custom_provider_(\d+)$/.exec(String(keyId ?? ""));
    return match ? parseInt(match[1], 10) : -1;
}
