// Token accounting, one bucket per local day - the fold.
//
// The ledger is a plain object: {days: {"2026-08-31": {input, output, total,
// requests, ok, err}}, allTime: {...}}. Every function copies, never
// mutates; the singleton owns file plumbing only. Dialects that report no
// usage send -1s: the request still counts, tokens do not.
.pragma library

function _bucket(existing) {
    var b = existing || {};
    return { input: b.input || 0, output: b.output || 0, total: b.total || 0,
             requests: b.requests || 0, ok: b.ok || 0, err: b.err || 0 };
}

function _add(bucket, tokens, ok) {
    var out = _bucket(bucket);
    if (tokens && (tokens.total || 0) > 0) {
        out.input += Math.max(0, tokens.input || 0);
        out.output += Math.max(0, tokens.output || 0);
        out.total += tokens.total;
    }
    out.requests += 1;
    if (ok) out.ok += 1; else out.err += 1;
    return out;
}

function withResponse(data, dayKey, tokens, ok) {
    var d = data || {};
    var days = {};
    for (var k in (d.days || {})) days[k] = d.days[k];
    days[dayKey] = _add(days[dayKey], tokens, ok);
    return { days: days, allTime: _add(d.allTime, tokens, ok) };
}

// Sum over day keys >= sinceKey (string compare works for yyyy-MM-dd).
function totalsSince(data, sinceKey) {
    var out = _bucket(null);
    var days = (data || {}).days || {};
    for (var k in days) {
        if (k < sinceKey) continue;
        var b = days[k];
        out.input += b.input || 0; out.output += b.output || 0;
        out.total += b.total || 0; out.requests += b.requests || 0;
        out.ok += b.ok || 0; out.err += b.err || 0;
    }
    return out;
}

// Days older than keepFromKey go; allTime keeps the full story.
function pruned(data, keepFromKey) {
    var d = data || {};
    var days = {};
    for (var k in (d.days || {}))
        if (k >= keepFromKey) days[k] = d.days[k];
    return { days: days, allTime: _bucket(d.allTime) };
}
