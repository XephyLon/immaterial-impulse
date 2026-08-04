import QtTest
import "../modules/common/functions/weatherForecast.js" as WeatherForecast

// Turning either provider's response into a row of day cards is arithmetic over
// a flat list, and every way of getting it wrong produces a plausible-looking
// row rather than an error: the wrong day's icon, one window's temperature
// range presented as the day's, or today's label on tomorrow's card.
TestCase {
    name: "WeatherForecastTest"

    function owmEntry(stamp, low, high, id) {
        return { dt_txt: stamp, main: { temp_min: low, temp_max: high }, weather: [{ id: id }] };
    }

    // OWM's list is three-hourly, so a day is eight entries and its range is the
    // extremes across all of them. Reading either off one entry reports that
    // three-hour window's range as the whole day's.
    function test_owmDayRangeSpansEveryEntryOfTheDay() {
        const days = WeatherForecast.dailyFromOwm([
            owmEntry("2026-08-04 00:00:00", 11, 14, 800),
            owmEntry("2026-08-04 12:00:00", 18, 24, 500),
            owmEntry("2026-08-04 21:00:00", 9, 16, 802)
        ]);
        compare(days.length, 1);
        compare(days[0].date, "2026-08-04");
        compare(days[0].high, 24, "the day's high is the highest of its entries");
        compare(days[0].low, 9, "the day's low is the lowest of its entries");
    }

    // A row keyed off the 00:00 entry says clear-and-cold for a day that rains
    // from lunchtime on, which is the opposite of what a forecast is for.
    function test_owmIconComesFromNearestMidday() {
        const days = WeatherForecast.dailyFromOwm([
            owmEntry("2026-08-04 00:00:00", 11, 14, 800),
            owmEntry("2026-08-04 09:00:00", 15, 19, 801),
            owmEntry("2026-08-04 15:00:00", 18, 24, 500),
            owmEntry("2026-08-04 21:00:00", 9, 16, 802)
        ]);
        compare(days[0].wCode, 801, "09:00 and 15:00 are both 3h out; the earlier wins the tie");

        const exact = WeatherForecast.dailyFromOwm([
            owmEntry("2026-08-04 00:00:00", 11, 14, 800),
            owmEntry("2026-08-04 12:00:00", 18, 24, 500)
        ]);
        compare(exact[0].wCode, 500, "an entry at midday beats one nine hours away");
    }

    // The first day of an OWM response is whatever is left of today, so it can
    // be a single evening entry. That is still a day and still gets a card.
    function test_owmGroupsIntoSeparateDaysInOrder() {
        const days = WeatherForecast.dailyFromOwm([
            owmEntry("2026-08-04 21:00:00", 9, 16, 802),
            owmEntry("2026-08-05 12:00:00", 12, 20, 500),
            owmEntry("2026-08-06 12:00:00", 13, 21, 600)
        ]);
        compare(days.length, 3);
        compare(days.map(day => day.date), ["2026-08-04", "2026-08-05", "2026-08-06"]);
        compare(days[0].high, 16, "a day with one entry takes that entry's range");
    }

    // OWM returns five days; the popup shows four.
    function test_owmIsCappedAtFourDays() {
        const entries = [];
        for (let day = 4; day <= 9; ++day)
            entries.push(owmEntry("2026-08-0" + day + " 12:00:00", 10, 20, 800));
        const days = WeatherForecast.dailyFromOwm(entries);
        compare(days.length, 4);
        compare(days[0].date, "2026-08-04", "the cap drops the far end, not the near one");
    }

    function test_owmSurvivesAJunkResponse() {
        compare(WeatherForecast.dailyFromOwm(undefined), []);
        compare(WeatherForecast.dailyFromOwm([]), []);
        compare(WeatherForecast.dailyFromOwm([{}, { dt_txt: 42 }, { dt_txt: "short" }]), []);
    }

    function wttrDay(date, lowC, highC, lowF, highF, hourly) {
        return {
            date: date, mintempC: lowC, maxtempC: highC, mintempF: lowF, maxtempF: highF,
            hourly: hourly
        };
    }

    // wttr.in already speaks the WWO codes Icons.weatherIconMap keys on, and its
    // `time` is an hhmm string with no separator - "300" is 03:00, not 300.
    function test_wttrPicksTheMiddayHourlyCode() {
        const days = WeatherForecast.dailyFromWttr([
            wttrDay("2026-08-04", "9", "21", "48", "70", [
                { time: "0", weatherCode: "113" },
                { time: "300", weatherCode: "116" },
                { time: "1200", weatherCode: "296" },
                { time: "2100", weatherCode: "119" }
            ])
        ], false);
        compare(days.length, 1);
        compare(days[0].wCode, 296);
        compare(days[0].high, 21);
        compare(days[0].low, 9);
    }

    function test_wttrFollowsTheUnitSetting() {
        const day = wttrDay("2026-08-04", "9", "21", "48", "70", []);
        compare(WeatherForecast.dailyFromWttr([day], false)[0].high, 21, "metric");
        compare(WeatherForecast.dailyFromWttr([day], true)[0].high, 70, "US customary");
        compare(WeatherForecast.dailyFromWttr([day], true)[0].low, 48, "US customary");
    }

    function test_wttrSurvivesAJunkResponse() {
        compare(WeatherForecast.dailyFromWttr(undefined, false), []);
        const days = WeatherForecast.dailyFromWttr([{}], false);
        compare(days.length, 1);
        compare(days[0].wCode, 0, "no hourly entries means no icon, not a crash");
        compare(days[0].high, null, "an absent reading is null, never 0 degrees");
        compare(days[0].low, null);
    }

    // A card shows whole degrees, but rounding null to 0 would print a
    // confident 0° for a reading that is simply not there.
    function test_absentReadingsStayNull() {
        const days = WeatherForecast.dailyFromOwm([
            { dt_txt: "2026-08-04 12:00:00", weather: [{ id: 800 }] }
        ]);
        compare(days[0].high, null);
        compare(days[0].low, null);
        compare(days[0].wCode, 800, "a missing temperature does not cost the icon");
    }

    function test_temperaturesAreRoundedToWholeDegrees() {
        const days = WeatherForecast.dailyFromOwm([
            owmEntry("2026-08-04 12:00:00", 9.4, 20.6, 800)
        ]);
        compare(days[0].high, 21);
        compare(days[0].low, 9);
    }

    // toISOString() is UTC. Using it would flip "today" hours early or late for
    // anyone not on UTC, and the row would label the wrong card for that window.
    // A UTC runner cannot tell the two apart at all, which is why
    // test_weather_forecast_contract.py re-runs this file east and west of it.
    function test_localIsoDateIsLocalNotUtc() {
        const date = new Date(2026, 7, 4, 23, 30, 0);   // local 4 Aug, 23:30
        compare(WeatherForecast.localIsoDate(date), "2026-08-04");
        compare(WeatherForecast.localIsoDate(new Date(2026, 0, 9, 0, 5, 0)), "2026-01-09",
                "single-digit months and days are padded");
    }

    function test_isTodayComparesTheWholeDate() {
        verify(WeatherForecast.isToday("2026-08-04", "2026-08-04"));
        verify(!WeatherForecast.isToday("2026-08-05", "2026-08-04"));
        verify(!WeatherForecast.isToday("", "2026-08-04"), "a dateless card is not today");
        verify(!WeatherForecast.isToday(undefined, "2026-08-04"));
    }

    // A bare "YYYY-MM-DD" parses as UTC midnight, which is the previous evening
    // west of UTC - so the card would be named for the wrong weekday.
    function test_shortDayNameIsTheDatesOwnWeekday() {
        compare(WeatherForecast.shortDayName("2026-08-04"),
                new Date(2026, 7, 4, 12, 0, 0).toLocaleDateString(undefined, { weekday: "short" }));
        compare(WeatherForecast.shortDayName(""), "");
        compare(WeatherForecast.shortDayName("not-a-date"), "");
    }
}
