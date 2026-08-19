import QtTest
import "../modules/common/functions/weatherHourly.js" as WeatherHourly

// The hourly row's decisions. Every one of them fails by drawing something
// plausible rather than by erroring: a chart of this morning at nine in the
// evening, five bars at the same height, a "00" that belongs to tomorrow, or a
// single bar at full height because it was scaled against itself.
TestCase {
    name: "WeatherHourlyTest"

    // Local, because that is what both a slot's hour and a slot's date mean.
    // Building the fixtures this way also keeps the file honest under the
    // far-east and far-west runs test_weather_forecast_contract.py drives it
    // through: an assertion written against a UTC hour would be a timezone
    // assumption wearing a fixture's clothes.
    function at(year, month, day, hour) {
        return new Date(year, month - 1, day, hour, 0, 0);
    }

    function owmEntry(when, temp, id) {
        return {
            dt: Math.floor(when.getTime() / 1000),
            // Deliberately a DIFFERENT clock from `dt`, which is what OWM does:
            // dt_txt is UTC. A reader that takes the hour from here is right
            // only on a UTC machine.
            dt_txt: "1999-01-01 00:00:00",
            main: { temp: temp },
            weather: [{ id: id }]
        };
    }

    // OWM's own documentation calls dt_txt UTC, so the hour on screen has to
    // come from the instant. On a UTC runner the two agree, which is exactly
    // why this fixture makes them disagree by a century.
    function test_owmSlotsTakeTheLocalHourFromTheInstantNotFromDtTxt() {
        const when = at(2026, 8, 4, 15);
        const slots = WeatherHourly.slotsFromOwm([owmEntry(when, 21.4, 500)]);
        compare(slots.length, 1);
        compare(slots[0].hour, 15, "the hour is the user's own clock");
        compare(slots[0].date, "2026-08-04");
        compare(slots[0].temp, 21.4, "the temperature is not rounded here; the label rounds it");
        compare(slots[0].wCode, 500);
        compare(slots[0].ms, when.getTime());
    }

    function test_owmSurvivesAJunkResponse() {
        compare(WeatherHourly.slotsFromOwm(undefined), []);
        compare(WeatherHourly.slotsFromOwm([]), []);
        compare(WeatherHourly.slotsFromOwm([{}, { dt: "nonsense" }, { dt: 0 }]), [],
                "an entry with no instant has no place on a time axis");
    }

    function test_owmKeepsASlotWhoseTemperatureIsMissing() {
        const slots = WeatherHourly.slotsFromOwm([
            { dt: Math.floor(at(2026, 8, 4, 15).getTime() / 1000), weather: [{ id: 800 }] }
        ]);
        compare(slots.length, 1, "the hour still exists");
        compare(slots[0].temp, null, "an absent reading is null, never 0 degrees");
    }

    function wttrDay(date, hourly) {
        return { date: date, hourly: hourly };
    }

    // "300" is 03:00, not three hundred.
    function test_wttrSlotsParseTheHhmmTimeAndFollowTheUnitSetting() {
        const day = wttrDay("2026-08-04", [
            { time: "0", tempC: "9", tempF: "48", weatherCode: "113" },
            { time: "300", tempC: "8", tempF: "46", weatherCode: "116" },
            { time: "1500", tempC: "21", tempF: "70", weatherCode: "296" }
        ]);
        const metric = WeatherHourly.slotsFromWttr([day], false);
        compare(metric.length, 3);
        compare(metric.map(slot => slot.hour), [0, 3, 15]);
        compare(metric[2].temp, 21);
        compare(metric[2].wCode, 296);
        compare(metric[2].ms, at(2026, 8, 4, 15).getTime(),
                "the timestamp is local, because wttr's own date and time are");

        const uscs = WeatherHourly.slotsFromWttr([day], true);
        compare(uscs[2].temp, 70, "US customary");
    }

    function test_wttrFlattensItsDaysInOrder() {
        const slots = WeatherHourly.slotsFromWttr([
            wttrDay("2026-08-04", [{ time: "2100", tempC: "12", tempF: "54", weatherCode: "113" }]),
            wttrDay("2026-08-05", [{ time: "0", tempC: "10", tempF: "50", weatherCode: "113" }])
        ], false);
        compare(slots.length, 2);
        compare(slots.map(slot => slot.date), ["2026-08-04", "2026-08-05"]);
    }

    // Both providers return their entries in order, so this is about a
    // malformed payload rather than a normal one - and a single bar out of
    // sequence has no other symptom.
    function test_slotsComeBackInTimeOrder() {
        const slots = WeatherHourly.slotsFromWttr([
            wttrDay("2026-08-05", [{ time: "0", tempC: "10", tempF: "50", weatherCode: "113" }]),
            wttrDay("2026-08-04", [{ time: "2100", tempC: "12", tempF: "54", weatherCode: "113" }])
        ], false);
        compare(slots.map(slot => slot.date), ["2026-08-04", "2026-08-05"]);
    }

    function test_wttrSurvivesAJunkResponse() {
        compare(WeatherHourly.slotsFromWttr(undefined, false), []);
        compare(WeatherHourly.slotsFromWttr([{}], false), [],
                "a day with no date cannot be placed on a time axis");
        compare(WeatherHourly.slotsFromWttr([wttrDay("2026-08-04", undefined)], false), []);
    }

    function series(hours) {
        return hours.map(entry => ({
            ms: at(entry[0], entry[1], entry[2], entry[3]).getTime(),
            date: entry[0] + "-" + (entry[1] < 10 ? "0" + entry[1] : entry[1])
                + "-" + (entry[2] < 10 ? "0" + entry[2] : entry[2]),
            hour: entry[3],
            temp: entry[4],
            wCode: 800
        }));
    }

    // wttr.in's first day always starts at 00:00, so most of what it returns is
    // already spent by mid-afternoon. Taking the head of the payload would draw
    // this morning's weather as a forecast for the rest of the day.
    function test_upcomingSkipsWhatHasAlreadyHappened() {
        const slots = series([
            [2026, 8, 4, 0, 11], [2026, 8, 4, 3, 10], [2026, 8, 4, 6, 12],
            [2026, 8, 4, 9, 16], [2026, 8, 4, 12, 20], [2026, 8, 4, 15, 21],
            [2026, 8, 4, 18, 18], [2026, 8, 4, 21, 14]
        ]);
        const shown = WeatherHourly.upcoming(slots, at(2026, 8, 4, 13).getTime(), 5);
        compare(shown.map(slot => slot.hour), [15, 18, 21],
                "only the hours still ahead, and the payload runs out at 21");
    }

    function test_upcomingIsCappedAndExcludesTheSlotOnTheHour() {
        const slots = series([
            [2026, 8, 4, 15, 21], [2026, 8, 4, 18, 18], [2026, 8, 4, 21, 14],
            [2026, 8, 5, 0, 12], [2026, 8, 5, 3, 11], [2026, 8, 5, 6, 13]
        ]);
        const shown = WeatherHourly.upcoming(slots, at(2026, 8, 4, 15).getTime(), 5);
        compare(shown.length, 5, "the window is capped");
        compare(shown[0].hour, 18,
                "a slot that has just started is what it is doing NOW, which the hero says");
    }

    // Midnight is the one label that could belong to either side of the
    // boundary, so the caller needs to be told where the day turns.
    function test_upcomingMarksTheDayBoundaryButNeverTheFirstSlot() {
        const slots = series([
            [2026, 8, 4, 21, 14], [2026, 8, 5, 0, 12], [2026, 8, 5, 3, 11]
        ]);
        const shown = WeatherHourly.upcoming(slots, at(2026, 8, 4, 20).getTime(), 5);
        compare(shown.map(slot => slot.dayBreak), [false, true, false]);

        const fromMidnight = WeatherHourly.upcoming(slots, at(2026, 8, 4, 23).getTime(), 5);
        compare(fromMidnight[0].hour, 0);
        compare(fromMidnight[0].dayBreak, false,
                "the first bar's day is the day the user is already in");
    }

    function test_upcomingReturnsNothingForAStalePayload() {
        const slots = series([[2026, 8, 4, 15, 21], [2026, 8, 4, 18, 18]]);
        compare(WeatherHourly.upcoming(slots, at(2026, 8, 9, 12).getTime(), 5), [],
                "a payload that is entirely in the past has nothing to forecast");
        compare(WeatherHourly.upcoming(undefined, 0, 5), []);
    }

    function test_theRangeIsTheShownWindowsOwn() {
        const shown = series([[2026, 8, 4, 15, 21], [2026, 8, 4, 18, 18], [2026, 8, 4, 21, 14]]);
        const range = WeatherHourly.chartRange(shown);
        compare(range.low, 14);
        compare(range.high, 21);
    }

    function test_theRangeIgnoresAbsentReadings() {
        const shown = series([[2026, 8, 4, 15, null], [2026, 8, 4, 18, 18]]);
        const range = WeatherHourly.chartRange(shown);
        compare(range.low, 18);
        compare(range.high, 18);
        compare(WeatherHourly.chartRange([]).low, null);
        compare(WeatherHourly.chartRange([]).high, null);
    }

    // The coldest hour of the window is still an hour, so its bar is still a
    // bar - a zero-height one reads as a hole in the row.
    function test_theColdestBarKeepsAVisibleFloorAndTheWarmestFillsTheTrack() {
        compare(WeatherHourly.barFraction(14, 14, 21), WeatherHourly.MIN_FRACTION);
        compare(WeatherHourly.barFraction(21, 14, 21), 1);
        const middle = WeatherHourly.barFraction(17.5, 14, 21);
        verify(middle > WeatherHourly.MIN_FRACTION && middle < 1,
               `a middling hour lands between the two: ${middle}`);
    }

    // Five identical degrees is a real still night, and it leaves nothing to
    // place anything between. Full height would claim heat and the floor would
    // claim cold.
    function test_aFlatWindowDrawsFlatBarsRatherThanDividingByZero() {
        compare(WeatherHourly.barFraction(18, 18, 18), WeatherHourly.FLAT_FRACTION);
    }

    function test_anAbsentReadingHasNoBarRatherThanAZeroOne() {
        compare(WeatherHourly.barFraction(null, 14, 21), null);
        compare(WeatherHourly.barFraction(undefined, 14, 21), null);
        compare(WeatherHourly.barFraction(18, null, null), null);
    }

    function test_aReadingOutsideTheRangeIsClampedIntoTheTrack() {
        compare(WeatherHourly.barFraction(30, 14, 21), 1);
        compare(WeatherHourly.barFraction(2, 14, 21), WeatherHourly.MIN_FRACTION);
    }

    // One bar is scaled against itself, so it is full height whatever the
    // temperature is: a confident drawing of nothing.
    function test_aSeriesTooShortToBeAChartIsNotDrawn() {
        const one = series([[2026, 8, 4, 15, 21]]);
        verify(!WeatherHourly.isRenderable(one));
        verify(!WeatherHourly.isRenderable([]));
        verify(!WeatherHourly.isRenderable(undefined));
        verify(WeatherHourly.isRenderable(
            series([[2026, 8, 4, 15, 21], [2026, 8, 4, 18, 18]])));
    }

    function test_aSeriesWithNoReadingsIsNotDrawnEither() {
        const blank = series([[2026, 8, 4, 15, null], [2026, 8, 4, 18, null], [2026, 8, 4, 21, 14]]);
        verify(!WeatherHourly.isRenderable(blank),
               "hour labels with nothing over them read as a rendering fault");
    }

    // There is no 12/24-hour switch in this shell - there is a Qt time format
    // string, and `ap` is its am/pm marker.
    function test_theClockFormatDecidesTheLabelStyle() {
        verify(!WeatherHourly.usesTwelveHourClock("hh:mm"));
        verify(!WeatherHourly.usesTwelveHourClock("HH:mm:ss"));
        verify(WeatherHourly.usesTwelveHourClock("h:mm ap"));
        verify(WeatherHourly.usesTwelveHourClock("hh:mm AP"));
        verify(!WeatherHourly.usesTwelveHourClock(""));
        verify(!WeatherHourly.usesTwelveHourClock(undefined));
        verify(!WeatherHourly.usesTwelveHourClock("dd/MMM"),
               "the `a` in a month name is not an am/pm marker");
    }

    function test_hourLabels() {
        compare(WeatherHourly.hourLabel(0, false), "00:00");
        compare(WeatherHourly.hourLabel(9, false), "09:00");
        compare(WeatherHourly.hourLabel(21, false), "21:00");
        compare(WeatherHourly.hourLabel(0, true), "12 AM");
        compare(WeatherHourly.hourLabel(9, true), "9 AM");
        compare(WeatherHourly.hourLabel(12, true), "12 PM");
        compare(WeatherHourly.hourLabel(21, true), "9 PM");
        compare(WeatherHourly.hourLabel(undefined, false), "");
    }
}
