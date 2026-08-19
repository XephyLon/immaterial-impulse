.pragma library
.import "weatherForecast.js" as Daily

// The hourly row in the bar's weather popup, as arithmetic.
//
// Neither provider is asked for anything new for this: OpenWeatherMap's
// /data/2.5/forecast - already fetched for the day cards - IS a three-hourly
// list, and wttr.in's `?format=j1` carries `weather[].hourly[]` inside the one
// response the current conditions come from. The whole feature is a second
// reading of two payloads the service already has.
//
// Everything here is a decision, which is why it is not in the QML: which
// slots are shown, how a bar is scaled, where a day boundary falls, and when
// there is not enough of a series to draw at all. Each of those is wrong in a
// way that renders perfectly - a chart of yesterday morning, a row of bars all
// the same height, a "00" label that belongs to tomorrow - so each has to be
// somewhere `tst_weather_hourly.qml` can call it.
//
// A `.pragma library` has no QML engine context, so nothing here touches `Qt`
// or a singleton (test_weather_forecast_contract.py holds both this file and
// weatherForecast.js to that). The locale, the clock format and "now" are all
// arguments; the caller has an engine context and passes them in.

// Five bars is what 340px of popup holds at a legible label size, and it is
// what the survey measured on the tree this is taken from
// (docs/p3drovfx-animation-research-2026-08-16.md §5.2).
var SLOT_COUNT = 5;

// Two bars is the floor for a CHART. One bar is scaled against itself, which
// makes it full height whatever the temperature is - a confident-looking
// drawing of nothing. Below this the row is not drawn at all.
var MIN_SLOTS = 2;

// The coldest bar in the window still has to be visible as a bar, or the row
// reads as four readings and a gap.
var MIN_FRACTION = 0.18;

// A window with no variation at all (five identical degrees, which a still
// night really does produce) has no low and no high to place anything between.
// Mid height says "flat"; full height would say "hot" and the floor would say
// "cold", and both would be a claim the data does not make.
var FLAT_FRACTION = 0.55;

function _pad2(value) {
    return value < 10 ? "0" + value : String(value);
}

// A temperature, or null if there isn't one.
//
// `Number(null)` is 0 and `isFinite(0)` is true, so the obvious guard - convert
// and test - reads a missing reading as a confident zero degrees: a bar at the
// floor, a "0°" label, and a window range dragged down to it. wttr.in hands
// these over as strings ("21"), so the conversion cannot simply be dropped
// either; the null-ish cases have to be refused before it.
function _reading(value) {
    if (value === null || value === undefined || value === "")
        return null;
    var number = Number(value);
    return isFinite(number) ? number : null;
}

// OpenWeatherMap's three-hourly list, normalised.
//
// Keyed on `dt` - the instant - and NOT on `dt_txt`, which OWM documents as
// UTC. `dailyFromOwm` groups by the `dt_txt` date because a day's card only
// needs to be a day apart from its neighbours, but an HOUR label read off it
// is the user's own clock wrong by their whole UTC offset, and it is right on
// the CI runner and on any machine in London. So the local hour and the local
// date both come from the timestamp.
function slotsFromOwm(list) {
    var slots = [];
    (list || []).forEach(function (entry) {
        var seconds = Number(entry && entry.dt);
        if (!isFinite(seconds) || seconds <= 0)
            return;
        var when = new Date(seconds * 1000);
        slots.push({
            ms: when.getTime(),
            date: Daily.localIsoDate(when),
            hour: when.getHours(),
            temp: _reading(entry && entry.main && entry.main.temp),
            wCode: Number(entry && entry.weather && entry.weather[0] && entry.weather[0].id) || 0
        });
    });
    return _sorted(slots);
}

// wttr.in's `weather[].hourly[]`, flattened across its three days.
//
// Both of its time fields are already local to the requested location: `date`
// is "YYYY-MM-DD" and `time` is an hhmm string with no separator ("0", "300",
// ... "2100"), which is why the hour is a division rather than a slice.
//
// The date is parsed field by field rather than through `new Date(string)`: a
// bare "YYYY-MM-DD" is read as UTC midnight, which is the previous evening west
// of UTC, and every slot of the day would be filed under the wrong date.
function slotsFromWttr(weather, useUSCS) {
    var slots = [];
    (weather || []).forEach(function (day) {
        var date = (day && day.date) || "";
        var parts = date.split("-");
        var year = Number(parts[0]);
        var month = Number(parts[1]);
        var dayOfMonth = Number(parts[2]);
        // A day with no date, or one whose date is not a date, cannot be placed
        // on a time axis at all. The NaN test is the whole of the check: a
        // missing field is `undefined`, which converts to NaN, so a separate
        // length test could never fire on its own.
        if (!isFinite(year) || !isFinite(month) || !isFinite(dayOfMonth))
            return;
        ((day && day.hourly) || []).forEach(function (entry) {
            var raw = Number((entry && entry.time) || 0);
            if (!isFinite(raw))
                return;
            var hour = Math.floor(raw / 100);
            slots.push({
                ms: new Date(year, month - 1, dayOfMonth, hour).getTime(),
                date: date,
                hour: hour,
                temp: _reading(useUSCS ? (entry && entry.tempF) : (entry && entry.tempC)),
                wCode: Number(entry && entry.weatherCode) || 0
            });
        });
    });
    return _sorted(slots);
}

// The slots the row shows: the next `limit` that have not started yet.
//
// Strictly ahead of `now`, because what it is doing at this minute is the hero
// card's job and a bar labelled 15 while the clock says 16:30 reads as a stale
// popup. This is also the whole of the day-boundary handling: wttr.in's first
// day always begins at 00:00, so at any time after breakfast most of what it
// returns is already spent, and a row that took the first five entries of the
// payload would be a chart of this morning until midnight. The list is
// flattened across days before it is cut, so the window rolls into tomorrow on
// its own.
//
// `dayBreak` marks the first slot of a date the previous shown slot did not
// have - never the first slot, whose day is the day the user is already in.
// The caller labels it with the weekday instead of the hour: "00" on its own
// is the one label that could belong to either side of the boundary.
function upcoming(slots, nowMs, limit) {
    var wanted = (limit === undefined || limit === null) ? SLOT_COUNT : limit;
    var ahead = [];
    (slots || []).forEach(function (slot) {
        if (slot && isFinite(slot.ms) && slot.ms > nowMs)
            ahead.push(slot);
    });
    return ahead.slice(0, Math.max(0, wanted)).map(function (slot, index, shown) {
        return {
            ms: slot.ms,
            date: slot.date,
            hour: slot.hour,
            temp: slot.temp,
            wCode: slot.wCode,
            dayBreak: index > 0 && !!slot.date && slot.date !== shown[index - 1].date
        };
    });
}

// The temperature range the bars are drawn against: the shown window's own
// extremes, not the day's and not the provider's. A five-slot window that
// spans two degrees should show two degrees of shape, which is what makes the
// row readable at a glance; scaling against a fixed range would draw every
// mild day as a flat line.
function chartRange(slots) {
    var low = null;
    var high = null;
    (slots || []).forEach(function (slot) {
        var temp = _reading(slot && slot.temp);
        if (temp === null)
            return;
        low = (low === null) ? temp : Math.min(low, temp);
        high = (high === null) ? temp : Math.max(high, temp);
    });
    return { low: low, high: high };
}

// A bar's height as a fraction of its track. `null` for a slot with no reading:
// an absent temperature is not a zero-height bar, which would read as the
// coldest hour of the window.
function barFraction(temp, low, high) {
    var value = _reading(temp);
    var bottom = _reading(low);
    var top = _reading(high);
    if (value === null || bottom === null || top === null)
        return null;
    if (top === bottom)
        return FLAT_FRACTION;
    var scaled = MIN_FRACTION + (1 - MIN_FRACTION) * (value - bottom) / (top - bottom);
    return Math.max(MIN_FRACTION, Math.min(1, scaled));
}

// Whether there is a chart here at all.
//
// Counted in READINGS rather than in slots, which answers both ways of having
// too little at once: a payload that is nearly spent, and a payload whose
// temperatures are missing. Both end as a row of hour labels with nothing over
// them, which looks like a rendering fault rather than like a provider that
// answered thinly - so the caller hides the section instead. A separate length
// test would be a second condition that can never fire on its own, since a
// reading needs a slot to sit in.
function isRenderable(slots) {
    var withReadings = 0;
    (slots || []).forEach(function (slot) {
        if (_reading(slot && slot.temp) !== null)
            withReadings++;
    });
    return withReadings >= MIN_SLOTS;
}

// The shell has no 12/24-hour switch - it has `Config.options.time.format`, a
// Qt time format string - so the row reads the clock the user already set
// rather than growing a setting of its own. `ap`/`AP` is Qt's am/pm marker and
// its presence is what makes a format twelve-hour.
function usesTwelveHourClock(timeFormat) {
    return /(^|[^a-zA-Z])(ap|AP)([^a-zA-Z]|$)/.test(String(timeFormat || ""));
}

// Built by hand rather than through a Date's locale methods, because this file
// has no engine context to hand one a `Qt.locale()` - and because QtQml's
// overload takes (locale, format) where ECMAScript takes an options object, so
// the browser spelling silently returns a different string here.
function hourLabel(hour, twelveHour) {
    var value = Number(hour);
    if (!isFinite(value))
        return "";
    var normalized = ((Math.floor(value) % 24) + 24) % 24;
    if (!twelveHour)
        return _pad2(normalized) + ":00";
    var display = normalized % 12;
    return (display === 0 ? 12 : display) + (normalized < 12 ? " AM" : " PM");
}

// Both providers return their entries in order, so this defends against a
// malformed payload rather than against a normal one - but a single
// out-of-order entry would put a bar out of sequence with no other symptom.
function _sorted(slots) {
    return slots.sort(function (left, right) {
        return left.ms - right.ms;
    });
}
