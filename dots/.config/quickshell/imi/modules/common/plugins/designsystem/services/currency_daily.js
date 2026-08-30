.pragma library

// The currency widget's month of daily closes, as arithmetic.
//
// Unlike the 24-hour ring (currency_history.js), which is what the shell
// itself observed, this layer is fetched: the rates dataset publishes one
// snapshot per day at a dated URL, and one date's file carries EVERY
// currency against the base - so the base's 30-day chart and all four
// quotes' 7-day trends cost the same ~30 cached CDN files, refetched only
// as dates go missing (one new file per day once the store is warm).
//
// The store is { base: "EGP", days: { "2026-08-28": { USD: 50.03, ... } } },
// rates already in the display direction (target per one quote unit, the
// same convention CurrencyService.rates carries). Every function is pure;
// the service owns the fetching and persistence around it.

var DAYS_KEPT = 31;   // 30 on the chart, one of slack for timezone edges

function dateKey(t) {
    var d = new Date(t);
    var month = String(d.getUTCMonth() + 1).padStart(2, "0");
    var day = String(d.getUTCDate()).padStart(2, "0");
    return d.getUTCFullYear() + "-" + month + "-" + day;
}

// The dates a warm store should hold, oldest first. Yesterday backwards:
// today's snapshot appears partway through the day (and 404s before it
// does), and the live rate already says what today is.
function wantedDates(now, count) {
    var dates = [];
    for (var i = count; i >= 1; i--)
        dates.push(dateKey(now - i * 86400000));
    return dates;
}

// What a fetch pass still needs, oldest first. A date the store holds - or
// one recorded as unavailable - is not refetched.
function missingDates(store, now, count, unavailable) {
    var have = store && store.days ? store.days : {};
    var skip = unavailable || {};
    return wantedDates(now, count).filter(function(date) {
        return have[date] === undefined && skip[date] !== true;
    });
}

// A fetched snapshot folded in. A change of base clears the store, exactly
// as it clears the ring - old numbers answer a different question.
function foldSnapshot(store, base, date, ratesIntoTarget, now) {
    var next = { base: base, days: {} };
    var have = store && store.base === base && store.days ? store.days : {};
    var keep = {};
    var wanted = wantedDates(now, DAYS_KEPT);
    for (var i = 0; i < wanted.length; i++) keep[wanted[i]] = true;
    for (var key in have)
        if (keep[key]) next.days[key] = have[key];
    if (keep[date] && ratesIntoTarget && Object.keys(ratesIntoTarget).length > 0)
        next.days[date] = ratesIntoTarget;
    return next;
}

// The daily closes of one code over the last `count` days, oldest first,
// with gaps simply absent. [{ date, value }].
function closesFor(store, code, now, count) {
    var out = [];
    if (!store || !store.days) return out;
    var wanted = wantedDates(now, count);
    for (var i = 0; i < wanted.length; i++) {
        var table = store.days[wanted[i]];
        var value = table ? Number(table[code]) : NaN;
        if (Number.isFinite(value) && value > 0)
            out.push({ date: wanted[i], value: value });
    }
    return out;
}

// The chart series, normalised to the unit box (x by day order, y across
// the observed range, a flat line pinned mid-height), plus the trend's
// direction (last close against first, with the same dead band the 24h
// movement uses). Empty below two closes - the honest-quiet rule.
var FLAT_PCT = 0.005;
function trendFor(store, code, now, count) {
    var closes = closesFor(store, code, now, count);
    if (closes.length < 2) return { points: [], direction: 0 };
    var lo = Infinity, hi = -Infinity;
    for (var i = 0; i < closes.length; i++) {
        lo = Math.min(lo, closes[i].value);
        hi = Math.max(hi, closes[i].value);
    }
    var span = hi - lo;
    // A flat month draws no line (same reasoning as the 24h series): the
    // caption and the movement column carry the flatness in words.
    if (span <= 0) return { points: [], direction: 0 };
    var points = closes.map(function(close, index) {
        return {
            x: closes.length > 1 ? index / (closes.length - 1) : 0,
            y: 1 - (close.value - lo) / span
        };
    });
    var first = closes[0].value, last = closes[closes.length - 1].value;
    var pct = (last - first) / first * 100;
    return {
        points: points,
        direction: Math.abs(pct) < FLAT_PCT ? 0 : (pct > 0 ? 1 : -1)
    };
}
