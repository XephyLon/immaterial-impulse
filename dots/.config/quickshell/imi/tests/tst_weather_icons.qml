import QtTest
import qs.modules.common

// The two weather providers report conditions in different, overlapping code
// schemes, and nothing in a code itself says which. An OpenWeatherMap id looked
// up in the WWO table matches nothing and falls through to "clear" - so the bar
// popup drew a clear sky through every storm for anyone on that provider, with
// no error anywhere.
TestCase {
    name: "WeatherIconTest"

    function test_owmCodesNoLongerFallThroughToClear() {
        // Real OWM conditions, none of them clear, all of which missed the WWO
        // table entirely and came back as a clear sky.
        const missed = [502, 601, 741, 804];
        for (const code of missed) {
            const wwo = Icons.getWeatherIcon(code);
            verify(wwo === "clear_day" || wwo === "clear_night",
                   "OWM code " + code + " is expected to miss the WWO table, got " + wwo);
            const owm = Icons.getProviderWeatherIcon("owm", code, false);
            verify(owm !== "clear_day" && owm !== "clear_night",
                   "OWM code " + code + " still resolves to a clear sky: " + owm);
        }
    }

    // Falling through to clear is only the loud half. The two schemes overlap
    // numerically, so some OWM ids land on a WWO entry and come back confidently
    // wrong instead - which no "is it clear?" check would ever notice.
    function test_anOwmCodeThatCollidesWithAWwoEntryIsStillWrong() {
        // OWM 302 is heavy drizzle. WWO 302 is moderate rain *shown as hail*.
        compare(Icons.getWeatherIcon(302), "weather_hail",
                "the collision this guards against");
        compare(Icons.getProviderWeatherIcon("owm", 302, false), "rainy");

        // OWM 200 is a thunderstorm and so is WWO 200, so that one agrees by
        // luck. Pinned so the agreement is on the record as a coincidence.
        compare(Icons.getWeatherIcon(200), "thunderstorm");
        compare(Icons.getProviderWeatherIcon("owm", 200, false), "thunderstorm");
    }

    function test_owmGroupsMapToTheirConditions() {
        compare(Icons.getProviderWeatherIcon("owm", 200, false), "thunderstorm");
        compare(Icons.getProviderWeatherIcon("owm", 302, false), "rainy", "drizzle");
        compare(Icons.getProviderWeatherIcon("owm", 502, false), "rainy");
        compare(Icons.getProviderWeatherIcon("owm", 601, false), "snowing");
        compare(Icons.getProviderWeatherIcon("owm", 741, false), "foggy", "atmosphere");
        compare(Icons.getProviderWeatherIcon("owm", 804, false), "cloud", "overcast");
    }

    // 800 is the only exact id OWM defines; 801-804 are increasing cloud cover,
    // so the boundary between "partly cloudy" and "cloudy" is a real decision.
    function test_owmCloudCoverBoundary() {
        compare(Icons.getProviderWeatherIcon("owm", 800, false), "clear_day");
        compare(Icons.getProviderWeatherIcon("owm", 801, false), "partly_cloudy_day");
        compare(Icons.getProviderWeatherIcon("owm", 802, false), "partly_cloudy_day");
        compare(Icons.getProviderWeatherIcon("owm", 803, false), "cloud");
    }

    function test_owmHonoursTheNightVariant() {
        compare(Icons.getProviderWeatherIcon("owm", 800, true), "clear_night");
        compare(Icons.getProviderWeatherIcon("owm", 801, true), "partly_cloudy_night");
        compare(Icons.getProviderWeatherIcon("owm", 502, true), "rainy",
                "rain looks the same at night");
    }

    // wttr.in speaks WWO already, so its codes must keep resolving exactly as
    // they did through the existing table.
    function test_wttrCodesStillGoThroughTheWwoTable() {
        compare(Icons.getProviderWeatherIcon("wttr", 113, false), "clear_day");
        compare(Icons.getProviderWeatherIcon("wttr", 113, true), "clear_night");
        compare(Icons.getProviderWeatherIcon("wttr", 296, false), "rainy");
        compare(Icons.getProviderWeatherIcon("wttr", 395, false), "snowing");
        compare(Icons.getProviderWeatherIcon("wttr", 200, false), "thunderstorm");
    }

    // A day card must never take the night variant: Thursday's forecast is not
    // about what the sky looks like tonight.
    function test_theNightFlagIsTheCallersToChoose() {
        compare(Icons.getProviderWeatherIcon("wttr", 113, false), "clear_day");
        compare(Icons.getProviderWeatherIcon("owm", 800, false), "clear_day");
    }

    function test_anUnknownCodeStillDegradesToClear() {
        compare(Icons.getProviderWeatherIcon("owm", 0, false), "clear_day");
        compare(Icons.getProviderWeatherIcon("wttr", 99999, true), "clear_night");
    }
}
