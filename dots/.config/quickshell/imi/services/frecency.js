.pragma library

// Launch-history ranking for the app search: how often an app is launched, and
// how recently, folded into one number that nudges the match order.
//
// Pure functions over a plain object so tests/tst_frecency.qml can exercise
// every shape the store can be in - including the ones that matter most, which
// are the broken ones. services/AppUsage.qml owns the file; this owns the
// arithmetic.
//
// The store keeps a bounded list of launch timestamps per app rather than a
// decayed running score, because a decayed score has to be rewritten for every
// app on every read to stay honest, and a stale one is indistinguishable from
// a correct one. Timestamps are re-scored from `now` at every query, so a store
// that has sat untouched for a month ranks correctly the moment it is read.

var STORE_VERSION = 1;

var MINUTE = 60 * 1000;
var HOUR = 60 * MINUTE;
var DAY = 24 * HOUR;
var WEEK = 7 * DAY;
var MONTH = 30 * DAY;

// Five windows, coarsening outwards. The weights are ratios rather than
// measurements: one launch in the last hour is worth two yesterday, five last
// week, twenty last month and a hundred at any point before that. What they
// have to produce is an order, and the shape - steep near now, flat far away -
// is what makes "the thing I have been using today" win without letting one
// click beat a year of habit.
var BUCKETS = [
    { within: HOUR, weight: 100 },
    { within: DAY, weight: 50 },
    { within: WEEK, weight: 20 },
    { within: MONTH, weight: 5 }
];
var OLDER_WEIGHT = 1;

// Bounds, so a store that is never pruned by anything else cannot grow without
// limit. Launches past the cap are not lost - they collapse into `total`, and
// `total` minus the retained list is what earns OLDER_WEIGHT.
var MAX_LAUNCHES_PER_APP = 32;
var MAX_APPS = 256;

// How far frecency may move a match. `boost` multiplies the match score by
// between 1 and 1 + BOOST_CEILING, so a heavily used app can overtake a
// slightly better textual match and cannot overtake a much better one - typing
// "fir" still puts Firefox above Firewall Config, and typing "chrome" never
// promotes Firefox no matter how often it is launched. HALF_BOOST is the score
// at which half the ceiling is reached: one launch in the last hour.
var BOOST_CEILING = 1.0;
var HALF_BOOST = 100;

function emptyStore() {
    return { "version": STORE_VERSION, "apps": {} };
}

function _entryFor(store, appId) {
    if (!store || !store.apps)
        return null;
    var entry = store.apps[appId];
    if (!entry || !Array.isArray(entry.launches))
        return null;
    return entry;
}

/**
 * The store held in `text`, or null for anything unusable.
 *
 * Null rather than a repaired store on purpose: the caller's fallback is an
 * empty store, and an empty store makes every frecency score 0, which makes
 * `boost` the identity - so a corrupt file degrades to plain match-order
 * ranking by construction rather than by a special case anyone has to
 * remember to write. This is derived data; nothing a user typed is in it.
 */
function parseStore(text) {
    if (text === undefined || text === null || String(text).trim().length === 0)
        return null;
    var parsed;
    try {
        parsed = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed))
        return null;
    if (parsed.apps === null || typeof parsed.apps !== "object" || Array.isArray(parsed.apps))
        return null;

    var store = emptyStore();
    for (var id in parsed.apps) {
        var entry = parsed.apps[id];
        if (entry === null || typeof entry !== "object" || Array.isArray(entry))
            continue;
        var launches = Array.isArray(entry.launches)
            ? entry.launches.filter(function (ts) { return typeof ts === "number" && isFinite(ts); })
            : [];
        var total = typeof entry.total === "number" && isFinite(entry.total)
            ? Math.max(entry.total, launches.length)
            : launches.length;
        if (launches.length === 0 && total === 0)
            continue;
        store.apps[String(id)] = { "launches": launches.slice(-MAX_LAUNCHES_PER_APP), "total": total };
    }
    return store;
}

function serializeStore(store) {
    return JSON.stringify(store && store.apps ? store : emptyStore());
}

/**
 * `store` with one more launch of `appId` recorded at `now`.
 *
 * Returns a new object rather than mutating, so the caller can publish it as a
 * property change - a store mutated in place is a store nothing announces.
 */
function recordLaunch(store, appId, now) {
    var id = String(appId === undefined || appId === null ? "" : appId);
    var base = (store && store.apps) ? store : emptyStore();
    if (id.length === 0)
        return base;

    var next = { "version": STORE_VERSION, "apps": {} };
    for (var key in base.apps)
        next.apps[key] = base.apps[key];

    var existing = _entryFor(base, id);
    var launches = existing ? existing.launches.slice(0) : [];
    launches.push(typeof now === "number" ? now : Date.now());
    var total = (existing && typeof existing.total === "number" ? existing.total : 0) + 1;
    next.apps[id] = { "launches": launches.slice(-MAX_LAUNCHES_PER_APP), "total": total };

    return _prune(next, typeof now === "number" ? now : Date.now());
}

// Over the cap, the lowest-scoring apps go. An app the user has not launched
// in months is the one whose absence cannot change an order.
function _prune(store, now) {
    var ids = Object.keys(store.apps);
    if (ids.length <= MAX_APPS)
        return store;

    ids.sort(function (a, b) { return scoreFor(store, b, now) - scoreFor(store, a, now); });
    var pruned = { "version": STORE_VERSION, "apps": {} };
    for (var i = 0; i < MAX_APPS; i++)
        pruned.apps[ids[i]] = store.apps[ids[i]];
    return pruned;
}

function _weightForAge(age) {
    // A timestamp from the future is a clock that moved, not a launch that has
    // not happened yet; score it as "just now" rather than letting a negative
    // age fall through every window to OLDER_WEIGHT.
    var elapsed = age < 0 ? 0 : age;
    for (var i = 0; i < BUCKETS.length; i++) {
        if (elapsed < BUCKETS[i].within)
            return BUCKETS[i].weight;
    }
    return OLDER_WEIGHT;
}

/** How strongly `appId` is used, as of `now`. 0 for anything unknown. */
function scoreFor(store, appId, now) {
    var entry = _entryFor(store, String(appId === undefined || appId === null ? "" : appId));
    if (!entry)
        return 0;

    var at = typeof now === "number" ? now : Date.now();
    var score = 0;
    for (var i = 0; i < entry.launches.length; i++)
        score += _weightForAge(at - entry.launches[i]);

    // Launches that fell off the retained list still count, at the flattest
    // weight - a long-standing habit does not vanish because it happened more
    // than MAX_LAUNCHES_PER_APP launches ago.
    var forgotten = Math.max(0, entry.total - entry.launches.length);
    return score + forgotten * OLDER_WEIGHT;
}

/**
 * `matchScore` nudged by how much the app is used.
 *
 * Multiplicative and bounded, which gives three properties worth stating:
 * a zero frecency is the identity (so an empty, missing or corrupt store
 * leaves the match order exactly as it was), two apps with equal frecency keep
 * their relative order, and no amount of use can promote an app past one
 * matching more than twice as well.
 */
function boost(matchScore, frecencyScore) {
    var match = typeof matchScore === "number" && isFinite(matchScore) ? matchScore : 0;
    var frecency = typeof frecencyScore === "number" && isFinite(frecencyScore) && frecencyScore > 0
        ? frecencyScore : 0;
    return match * (1 + BOOST_CEILING * (frecency / (frecency + HALF_BOOST)));
}
