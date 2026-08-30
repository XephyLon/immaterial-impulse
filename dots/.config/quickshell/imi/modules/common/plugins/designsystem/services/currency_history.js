.pragma library

// The currency widget's 24-hour memory, as arithmetic.
//
// The rates API is a daily dataset - there is no hourly history to fetch -
// so the history is what the shell itself observed: one sample per
// successful refresh (hourly when healthy), persisted across restarts, and
// pruned to a day. The 3x1's chart line and the per-quote deltas both read
// it, which also makes them honest: they show the currency's movement as
// this machine saw it, not an interpolation of two daily closes.
//
// A sample is { t: epoch ms, base: "USD", rates: { EUR: 0.92, ... } }.
// Every function is pure; the service owns the persistence around it.

var WINDOW_MS = 24 * 3600 * 1000;
var PRUNE_MS = 25 * 3600 * 1000;   // one hour of slack past the window
var MAX_SAMPLES = 48;              // backstop against a fast-retry burst
var MIN_GAP_MS = 5 * 60 * 1000;    // two samples closer than this are one

// The ring with a new observation folded in. A change of base clears it -
// yesterday's EUR-per-USD says nothing about EUR-per-EGP - and a sample
// arriving hot on the last one's heels replaces it rather than queueing
// (the retry schedule can succeed twice in a minute after a network blip).
function pushSample(history, t, base, rates) {
    var list = Array.isArray(history) ? history.slice() : [];
    if (list.length > 0 && list[list.length - 1].base !== base)
        list = [];
    if (list.length > 0 && t - list[list.length - 1].t < MIN_GAP_MS)
        list.pop();
    list.push({ t: t, base: base, rates: rates || {} });
    while (list.length > MAX_SAMPLES) list.shift();
    return prune(list, t);
}

function prune(history, now) {
    var list = Array.isArray(history) ? history : [];
    return list.filter(function(sample) {
        return sample && typeof sample.t === "number"
            && now - sample.t <= PRUNE_MS && sample.t <= now;
    });
}

// The rate closest to `ago` milliseconds back - the oldest sample inside
// the window when nothing reaches that far, so a widget placed this morning
// still shows movement since this morning rather than nothing. Null when
// the history holds no usable point BESIDES the newest one: a delta of a
// value against itself is a claim of stability nothing measured.
function rateAgo(history, code, now, ago) {
    var list = prune(history, now);
    if (list.length < 2) return null;
    var target = now - ago;
    var best = null;
    for (var i = 0; i < list.length - 1; i++) {
        var value = Number(list[i].rates?.[code]);
        if (!Number.isFinite(value) || value <= 0) continue;
        if (best === null || Math.abs(list[i].t - target) < Math.abs(best.t - target))
            best = { t: list[i].t, value: value };
    }
    return best ? best.value : null;
}

// { pct, abs, direction } of `current` against the window-ago rate, or null.
// direction is -1 / 0 / 1; the dead band keeps a sixth-decimal wobble from
// flickering the arrow between up and down.
var FLAT_PCT = 0.005;
function changeOf(history, code, now, current) {
    var then = rateAgo(history, code, now, WINDOW_MS);
    var value = Number(current);
    if (then === null || !Number.isFinite(value) || value <= 0) return null;
    var pct = (value - then) / then * 100;
    return {
        pct: pct,
        abs: value - then,
        direction: Math.abs(pct) < FLAT_PCT ? 0 : (pct > 0 ? 1 : -1)
    };
}

// The chart line: the window's samples of one code, normalised to 0..1 in
// both axes - x by time across the window, y across the observed range with
// a flat line pinned to the middle. Empty (never null) below two points;
// the widget keeps its decorative curve until there is something true to
// draw.
function seriesFor(history, code, now) {
    var list = prune(history, now);
    var points = [];
    for (var i = 0; i < list.length; i++) {
        var value = Number(list[i].rates?.[code]);
        if (Number.isFinite(value) && value > 0)
            points.push({ t: list[i].t, value: value });
    }
    if (points.length < 2) return [];
    var t0 = now - WINDOW_MS;
    var lo = Infinity, hi = -Infinity;
    for (var j = 0; j < points.length; j++) {
        lo = Math.min(lo, points[j].value);
        hi = Math.max(hi, points[j].value);
    }
    var span = hi - lo;
    // A day with no movement is not a shape worth drawing: normalised, it
    // is a straight line through the middle of the band, which on the card
    // is indistinguishable from nothing ("the graph line is gone" - the
    // maintainer, looking at exactly that). The widget keeps its decorative
    // curve until the day has a real shape; the movement columns already
    // say "flat" honestly, in numbers.
    if (span <= 0) return [];
    return points.map(function(point) {
        return {
            x: Math.max(0, Math.min(1, (point.t - t0) / WINDOW_MS)),
            y: 1 - (point.value - lo) / span
        };
    });
}

// "2m ago" for the footer stamp. Empty until anything succeeded.
function agoLabel(now, lastSuccess) {
    if (!lastSuccess) return "";
    // A refresh that landed after the widget's minute-tick reads as the
    // future; that is the first minute after every success, not an error.
    if (lastSuccess > now) return "just now";
    var minutes = Math.floor((now - lastSuccess) / 60000);
    if (minutes < 1) return "just now";
    if (minutes < 60) return minutes + "m ago";
    var hours = Math.floor(minutes / 60);
    if (hours < 24) return hours + "h ago";
    return Math.floor(hours / 24) + "d ago";
}
