.pragma library

// Where the sun is between today's sunrise and sunset, as arithmetic.
//
// The weather card draws this as a line across its background - the currency
// sparkline's place in the composition, except this one means something.
//
// The awkward part is not the curve, it is the clock: `Weather.data.sunrise`
// and `.sunset` are STRINGS from both providers, and not the same strings.
// OpenWeatherMap's epoch is formatted to "6:29:14 AM" (en-US, with seconds)
// before it is published, and wttr.in hands over its own "06:29 AM" already
// formatted. Neither is a Date, and parsing either with `new Date(...)` gets
// an Invalid Date - so this reads the clock itself.

// How much night the card shows past each horizon, as a fraction of the
// daylight, and how much of the sine's depth the night tails keep at their
// deepest. Named here rather than left as literals on the canvas because the
// arc's ASPECT - how wide the day is against how far the curve rises in it -
// is what decides whether a span can carry the arc at all, and a test cannot
// ask that question of a number sitting in a QML binding.
var NIGHT_MARGIN = 0.22;
var TAIL_FLATTEN = 0.35;

// Minutes since local midnight, or -1 when the string is not a clock. "0" is
// what both providers' parsers write when the field was missing, and it must
// not read as midnight - a sun that rises at 00:00 puts the dot in the wrong
// place all day rather than admitting it does not know.
function minutesFromClock(text) {
    if (typeof text !== "string") return -1;
    var match = text.match(/^\s*(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?\s*$/);
    if (!match) return -1;
    var hours = Number(match[1]);
    var minutes = Number(match[2]);
    if (minutes > 59) return -1;
    var meridiem = match[4] ? match[4].toLowerCase() : "";
    if (meridiem === "am") {
        if (hours > 12) return -1;
        if (hours === 12) hours = 0;          // 12:xx AM is after midnight
    } else if (meridiem === "pm") {
        if (hours > 12) return -1;
        if (hours !== 12) hours += 12;        // ...and 12:xx PM is midday
    } else if (hours > 23) {
        return -1;
    }
    return hours * 60 + minutes;
}

// How far through the daylight the given moment is, 0 at sunrise and 1 at
// sunset. Null when the answer is not knowable: an unparsed time, or a sunset
// that does not come after its sunrise (which is what a polar summer, a
// missing field or a provider hiccup looks like from here).
//
// Before sunrise and after sunset it CLAMPS rather than returning null: the
// dot belongs parked at the horizon it is nearest, and the caller decides
// whether to draw it dimmed.
function dayProgress(nowMinutes, sunriseText, sunsetText) {
    var rise = minutesFromClock(sunriseText);
    var set = minutesFromClock(sunsetText);
    if (rise < 0 || set < 0 || set <= rise) return null;
    var t = (nowMinutes - rise) / (set - rise);
    return Math.max(0, Math.min(1, t));
}

// True while the sun is actually up, which is a different question from where
// it would be: the arc is drawn either way, the disc is only filled by day.
function isDaylight(nowMinutes, sunriseText, sunsetText) {
    var rise = minutesFromClock(sunriseText);
    var set = minutesFromClock(sunsetText);
    if (rise < 0 || set < 0 || set <= rise) return false;
    return nowMinutes >= rise && nowMinutes <= set;
}

// The card shows MORE than the daylight: the curve carries on past both
// horizons and dips below them, which is the whole reason the horizon reads as
// a horizon rather than as a baseline the line happens to start on. `margin`
// is how much night to show at each end, as a fraction of the daylight.
//
// Returned in card coordinates: `uRise` and `uSet` are where sunrise and
// sunset fall across the width, both strictly inside 0..1.
function windowFor(margin) {
    var m = margin > 0 ? margin : 0.001;
    var total = 1 + 2 * m;
    return { uRise: m / total, uSet: (m + 1) / total };
}

// Where a point across the card sits in the day, as a phase: 0 at sunrise, 1
// at sunset, NEGATIVE before dawn and past 1 after dusk. Deliberately
// unclamped - the sign is what tells the caller which side of the horizon a
// stretch of curve belongs to.
function phaseAt(u, window) {
    return (u - window.uRise) / (window.uSet - window.uRise);
}

// The height of the curve at a phase, measured from the horizon. Positive is
// above it.
//
// The daylight stretch is a half-sine, which is the shape the two times
// actually justify. The NIGHT tails are that same sine with its amplitude
// eased away, so they level off toward the card's edges instead of plunging:
// a plain continued sine leaves at its steepest exactly where it is cut off,
// and a curve that is steepest at the edge of the frame reads as a fragment
// of something bigger rather than as a day.
//
// `tailFlatten` is how much of the sine's depth the tails keep at their
// deepest; the falloff between is smooth (a cosine ease), so there is no
// corner where day becomes night.
function heightAt(phase, rise, tailFlatten) {
    var raw = Math.sin(phase * Math.PI) * rise;
    if (phase >= 0 && phase <= 1) return raw;
    var flatten = tailFlatten === undefined ? TAIL_FLATTEN : tailFlatten;
    // How far into the night this is, in phase units, capped at half a period
    // (where the continued sine would bottom out).
    // Ease from full depth at the horizon to `flatten` of it further out, on
    // a cosine so the join at the horizon has no corner in it.
    var into = Math.min(1, (phase < 0 ? -phase : phase - 1) / 0.5);
    var eased = 0.5 - 0.5 * Math.cos(into * Math.PI);
    return raw * (1 - (1 - flatten) * eased);
}

// Where the curve is at a point across the card, in CARD coordinates - y
// grows downward, so the apex is the smallest number this returns.
//
// The marker rides the line the canvas strokes, and this is the one place
// that line is spelled. Written out at both call sites instead, the two agree
// only for as long as nobody edits one of them: a marker floating a few pixels
// off its own curve is not an error, does not warn, and looks like a rounding
// artefact rather than like two expressions that have drifted apart.
function curveY(u, window, horizonY, apexRise, tailFlatten) {
    return horizonY - heightAt(phaseAt(u, window), apexRise, tailFlatten);
}

// Where today's sun sits across the card, or null when the day is not
// knowable. Clamped to the card, so a sun deep in the night parks at the edge
// rather than being drawn off it.
function sunU(nowMinutes, sunriseText, sunsetText, window) {
    var rise = minutesFromClock(sunriseText);
    var set = minutesFromClock(sunsetText);
    if (rise < 0 || set < 0 || set <= rise) return null;
    var phase = (nowMinutes - rise) / (set - rise);
    var u = window.uRise + phase * (window.uSet - window.uRise);
    return Math.max(0, Math.min(1, u));
}
