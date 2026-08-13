.pragma library

// Neither weather provider describes a forecast as days, so turning one into a
// row of day cards is arithmetic over a flat list rather than a field lookup.
//
// wttr.in's `?format=j1` response already carries three days in `weather[]`,
// each with its own min/max and eight three-hourly entries - the forecast comes
// free with the request the service already makes. OpenWeatherMap splits it:
// /data/2.5/weather is current conditions only, and /data/2.5/forecast is a
// flat list of three-hourly entries that has to be grouped into days here.
//
// Both shapes collapse to the same `{ date, wCode, high, low }`, with `date` as
// a local "YYYY-MM-DD" so the caller can label it and temperatures already in
// whichever unit system was asked for.

// Four fits the popup's width at both providers' resolutions. wttr.in only ever
// returns three days, so that is what it shows; OWM's five-day list is cut here.
const MAX_DAYS = 4;

// The hour a day's icon is taken from. Not the first entry of the day: a
// forecast keyed off the 00:00 observation reads as clear-and-cold for a day
// that is in fact raining from lunchtime on, which is the opposite of what the
// row is for.
const ICON_HOUR = 12;

// Local calendar date as "YYYY-MM-DD".
//
// Deliberately not `toISOString().slice(0, 10)`, which is UTC: anywhere east or
// west of it that flips "today" hours early or late, and the row would put
// today's label on tomorrow's card for part of every day.
function localIsoDate(date) {
    const pad = (value) => (value < 10 ? "0" + value : String(value));
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate());
}

function isToday(isoDate, todayIsoDate) {
    return !!isoDate && isoDate === todayIsoDate;
}

// Short weekday name for a "YYYY-MM-DD" date, or "" if it is not one.
//
// Parsed at midday rather than at midnight: a bare "YYYY-MM-DD" is read as UTC
// midnight, which is the previous day's evening for anyone west of UTC, and the
// card would name the wrong weekday.
//
// A locale and a format string, NOT ECMAScript's options object. QtQml
// replaces `Date.prototype.toLocaleDateString` with an overload taking
// (locale, format), and it does not understand `{ weekday: "short" }` - it
// falls through to the locale's short DATE format, so every card read
// "8/14/26" where a browser would say "Fri". Nothing about that is visible
// from reading the call; it was measured in the engine.
//
// The locale is an argument because this file is a `.pragma library` and
// keeps itself free of `Qt` (test_weather_forecast_contract.py). The callers
// have an engine context and pass `Qt.locale()`; the arithmetic that has to
// be right whatever the locale is - parsing at midday so a bare
// "YYYY-MM-DD" is not read as the previous evening west of UTC - stays here.
function shortDayName(isoDate, locale) {
    if (!isoDate)
        return "";
    const parsed = new Date(isoDate + "T12:00:00");
    if (isNaN(parsed.getTime()))
        return "";
    return parsed.toLocaleDateString(locale, "ddd");
}

// OpenWeatherMap's /data/2.5/forecast `list`, grouped into days.
//
// Temperatures are already in the unit system the request asked for. Each entry
// carries a `temp_min`/`temp_max` for its own three-hour window, so a day's
// range is the extremes across all of its entries - reading either off a single
// entry gives that window's range and calls it the day's.
function dailyFromOwm(list) {
    const byDate = {};
    (list || []).forEach(entry => {
        const stamp = entry && entry.dt_txt;
        if (typeof stamp !== "string" || stamp.length < 13)
            return;
        const date = stamp.slice(0, 10);
        if (!byDate[date])
            byDate[date] = { date: date, wCode: 0, high: null, low: null, iconDistance: Infinity };
        const day = byDate[date];

        const high = Number(entry && entry.main && entry.main.temp_max);
        const low = Number(entry && entry.main && entry.main.temp_min);
        if (isFinite(high))
            day.high = (day.high === null) ? high : Math.max(day.high, high);
        if (isFinite(low))
            day.low = (day.low === null) ? low : Math.min(day.low, low);

        const distance = Math.abs(Number(stamp.slice(11, 13)) - ICON_HOUR);
        if (isFinite(distance) && distance < day.iconDistance) {
            day.iconDistance = distance;
            day.wCode = Number(entry && entry.weather && entry.weather[0] && entry.weather[0].id) || 0;
        }
    });
    return Object.keys(byDate).sort().slice(0, MAX_DAYS).map(date => _round(byDate[date]));
}

// wttr.in's `weather[]`, which is already one element per day.
//
// The min/max come ready-made; only the icon has to be chosen, from `hourly[]`
// whose `time` is an hhmm string without a separator ("0", "300" ... "2100").
// wttr already speaks the WWO codes Icons.weatherIconMap keys on, so the code
// passes straight through.
function dailyFromWttr(weather, useUSCS) {
    return (weather || []).slice(0, MAX_DAYS).map(day => {
        const entry = { date: (day && day.date) || "", wCode: 0, high: null, low: null };
        let iconDistance = Infinity;
        ((day && day.hourly) || []).forEach(hour => {
            const distance = Math.abs(Math.floor(Number((hour && hour.time) || 0) / 100) - ICON_HOUR);
            if (isFinite(distance) && distance < iconDistance) {
                iconDistance = distance;
                entry.wCode = Number(hour && hour.weatherCode) || 0;
            }
        });
        const high = Number(useUSCS ? (day && day.maxtempF) : (day && day.maxtempC));
        const low = Number(useUSCS ? (day && day.mintempF) : (day && day.mintempC));
        entry.high = isFinite(high) ? high : null;
        entry.low = isFinite(low) ? low : null;
        return _round(entry);
    });
}

// A card shows whole degrees. `null` stays null - an absent reading is not 0°.
function _round(day) {
    return {
        date: day.date,
        wCode: day.wCode,
        high: day.high === null ? null : Math.round(day.high),
        low: day.low === null ? null : Math.round(day.low)
    };
}
