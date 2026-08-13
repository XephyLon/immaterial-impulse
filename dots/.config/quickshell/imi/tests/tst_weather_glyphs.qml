import QtTest
import "../modules/common/plugins/designsystem/widgets/weather_glyphs.js" as Glyphs

// The desktop weather card's google-weather asset lookup.
//
// The bug this exists for: a weather code means nothing without the provider
// that reported it, and the card used to read wttr.in's World Weather Online
// codes through an OpenWeatherMap-shaped range table.
TestCase {
    name: "WeatherGlyphsTest"

    function test_the_owm_branch_is_unchanged() {
        // Deliberately pinned rather than retuned. This is what the card draws
        // today on the default provider; giving the other provider a table is
        // a separate question from re-deciding this one.
        compare(Glyphs.glyphFor("owm", 800, false), "clear_day");
        compare(Glyphs.glyphFor("owm", 800, true), "clear_night");
        compare(Glyphs.glyphFor("owm", 801, false), "partly_cloudy_day");
        compare(Glyphs.glyphFor("owm", 211, false), "strong_thunderstorms");
        compare(Glyphs.glyphFor("owm", 500, false), "heavy_rain");
        compare(Glyphs.glyphFor("owm", 601, false), "heavy_snow");
        compare(Glyphs.glyphFor("owm", 741, false), "haze_fog_dust_smoke");
        compare(Glyphs.glyphFor("owm", 804, false), "cloudy");
    }

    function test_wttr_codes_no_longer_read_as_openweathermap_ids() {
        // The two failures the split is for, and they are different shapes.
        // 113 is Sunny and falls past every OWM range into the fallback; 296
        // is Light rain and lands *inside* OWM's thunderstorm range, so it
        // came back confidently wrong rather than merely blank.
        compare(Glyphs.glyphFor("owm", 113, false), "cloudy", "the old reading of Sunny");
        compare(Glyphs.glyphFor("wttr", 113, false), "clear_day");
        compare(Glyphs.glyphFor("owm", 296, false), "strong_thunderstorms",
                "the old reading of Light rain");
        compare(Glyphs.glyphFor("wttr", 296, false), "showers_rain");
    }

    function test_wttr_conditions_map_to_their_own_class() {
        const cases = [
            [116, "partly_cloudy_day"], [122, "cloudy"], [143, "haze_fog_dust_smoke"],
            [200, "isolated_scattered_thunderstorms_day"], [230, "blizzard"],
            [266, "drizzle"], [308, "heavy_rain"], [320, "sleet_hail"],
            [326, "flurries"], [338, "heavy_snow"], [389, "strong_thunderstorms"]
        ];
        for (const pair of cases)
            compare(Glyphs.glyphFor("wttr", pair[0], false), pair[1], "WWO " + pair[0]);
    }

    function test_only_the_codes_with_two_assets_take_a_night_variant() {
        compare(Glyphs.glyphFor("wttr", 116, true), "partly_cloudy_night");
        compare(Glyphs.glyphFor("wttr", 353, true), "scattered_showers_night");
        // Rain at night is drawn the same way as rain in the daytime; there is
        // no `heavy_rain_night` asset and asking for one would render nothing.
        compare(Glyphs.glyphFor("wttr", 308, true), "heavy_rain");
        compare(Glyphs.glyphFor("wttr", 230, true), "blizzard");
    }

    function test_an_unknown_code_degrades_the_same_way_on_both_providers() {
        compare(Glyphs.glyphFor("wttr", 9999, false), "cloudy");
        compare(Glyphs.glyphFor("owm", 9999, false), "cloudy");
        compare(Glyphs.glyphFor("wttr", 0, false), "cloudy");
    }

    function test_a_code_arriving_as_a_string_still_resolves() {
        // `wCode` is Number()-ed by the service, but a card reading it out of
        // a forecast entry is one refactor away from a string, and a table
        // keyed on numbers would silently miss every one of them.
        compare(Glyphs.glyphFor("wttr", "113", false), "clear_day");
        compare(Glyphs.glyphFor("owm", "800", false), "clear_day");
    }
}
