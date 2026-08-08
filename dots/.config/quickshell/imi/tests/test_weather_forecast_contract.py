#!/usr/bin/env python3
"""Weather forecast pins: the wiring the unit tests cannot see.

`tst_weather_forecast.qml` proves the day-grouping arithmetic and
`tst_weather_icons.qml` proves the provider-aware icon lookup, both against the
real sources. Neither can see the service that has to call them, the second
OpenWeatherMap request the forecast depends on, or the popup that renders the
result - and each of those can break on its own without failing a single unit
test.

The URL pins are the load-bearing ones. `city` comes from config and from
shareable presets, and the existing calls carry a comment recording that they
were once spliced into a double-quoted `curl -s "${url}"` where `$()` and
backticks still expand. A new request built the old way would reopen that hole
in a file whose other three calls look correct.
"""
import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests"
FORECAST_QML_TEST = TESTS / "tst_weather_forecast.qml"
SERVICE = ROOT / "services/Weather.qml"
POPUP = ROOT / "modules/imi/bar/WeatherPopup.qml"
ICONS = ROOT / "modules/common/Icons.qml"
FORECAST_JS = ROOT / "modules/common/functions/weatherForecast.js"


def _function_body(source, name):
    """The body of a top-level `function <name>()`, by its closing indent.

    Not brace counting: these bodies contain template literals whose `${...}`
    braces defeat a naive count, which is how the first version of this pin
    matched nothing at all.
    """
    match = re.search(r"function " + re.escape(name) + r"\(.*?\n    \}", source, re.S)
    return match.group(0) if match else None


def _without_comments(source):
    """Prose about a singleton is not a use of one."""
    return re.sub(r"//[^\n]*", "", source)


# Same search order as run_tests.sh, which is the only thing that guarantees
# this binary exists at all.
_RUNNER_CANDIDATES = (
    "/usr/lib/qt6/bin/qmltestrunner",
    "/usr/lib64/qt6/bin/qmltestrunner",
    "/usr/lib/x86_64-linux-gnu/qt6/bin/qmltestrunner",
    "qmltestrunner-qt6",
    "qmltestrunner6",
    "qmltestrunner",
)


def _qmltestrunner():
    for candidate in _RUNNER_CANDIDATES:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
        found = shutil.which(candidate)
        if found:
            return found
    return None


class WeatherServiceForecastTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.service = SERVICE.read_text(encoding="utf-8")

    def test_the_service_exposes_a_forecast(self):
        self.assertRegex(self.service, r"property\s+var\s+forecast\s*:",
                         "Weather no longer publishes a forecast for widgets to read.")

    def test_both_providers_populate_it(self):
        """wttr.in gets it free; OWM needs a request of its own.

        A provider that never fills the property leaves that half of the users
        with a permanently empty row and nothing in the log.
        """
        self.assertIn("dailyFromWttr", self.service,
                      "the wttr.in response already carries three days of "
                      "forecast; not reading them wastes a request already made.")
        self.assertIn("dailyFromOwm", self.service,
                      "OpenWeatherMap's current-conditions endpoint has no "
                      "outlook, so /data/2.5/forecast has to be parsed.")

    def test_the_owm_forecast_request_is_actually_issued(self):
        """Parsing a response nothing asks for is a permanently empty row."""
        self.assertIn("api.openweathermap.org/data/2.5/forecast", self.service)
        body = _function_body(self.service, "getDataOwm")
        self.assertIsNotNone(body, "getDataOwm should exist")
        self.assertIn(
            "getForecastOwm()", body,
            "the forecast request must be issued alongside the current "
            "conditions, or it only ever runs if something else calls it.")

    def test_every_curl_call_passes_the_url_as_an_argv_element(self):
        """The city reaches these URLs from config and from shared presets.

        `curl -s "${url}"` through a shell still expands `$()` and backticks -
        a command-injection hole this file was hardened against once already.
        A new endpoint built the old way reopens it.
        """
        commands = re.findall(r"^\s*\w*\.?command\s*:?=\s*(.+)$", self.service, re.M)
        self.assertTrue(commands, "expected the service to build curl commands")
        for command in commands:
            self.assertRegex(
                command.strip(), r'^\["curl",\s*"-s",\s*[^"]*\]$|^\["curl",\s*"-s",\s*""\]$',
                f"a curl command is not a plain argv list ({command.strip()!r}); "
                "the URL must never be spliced into a shell string.")
        self.assertNotRegex(
            self.service, r'"\s*curl[^"]*\$\{',
            "a URL is being interpolated into a shell command string.")

    def test_the_forecast_endpoint_carries_the_key_and_the_unit_system(self):
        """A forecast in the wrong unit system next to a correct current
        temperature reads as the forecast being wrong, not the request."""
        body = _function_body(self.service, "getForecastOwm")
        self.assertIsNotNone(body, "getForecastOwm should exist")
        self.assertIn("appid=", body, "the forecast endpoint needs the API key too")
        self.assertIn("units=", body, "the forecast must be fetched in the "
                                      "configured unit system")
        self.assertIn("useUSCS", body)


class WeatherPopupForecastTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.popup = POPUP.read_text(encoding="utf-8")

    def test_the_popup_renders_the_forecast(self):
        self.assertIn("Weather.forecast", self.popup,
                      "nothing in the popup reads the forecast, so the service "
                      "populates a property no one shows.")
        self.assertRegex(self.popup, r"Repeater\s*\{[^}]*model:\s*Weather\.forecast",
                         "the forecast should be repeated into one card per day.")

    def test_an_empty_forecast_hides_the_row_rather_than_showing_blanks(self):
        """OWM fetches the forecast separately, so it can be absent while
        everything else on the popup is present."""
        self.assertRegex(self.popup, r"visible:\s*Weather\.forecast\.length\s*>\s*0",
                         "a row of blank cards reads as broken rather than as "
                         "a provider that has no forecast yet.")

    def test_the_popup_asks_for_provider_aware_icons(self):
        """Both the current conditions and every forecast card.

        `getWeatherIcon` is keyed on WWO codes only, so an OpenWeatherMap id
        either misses it entirely and draws a clear sky, or collides with an
        unrelated entry and draws the wrong condition confidently.
        """
        self.assertNotRegex(
            self.popup, r"Icons\.getWeatherIcon\(",
            "the popup still uses the WWO-only lookup, which is wrong for every "
            "OpenWeatherMap condition.")
        self.assertGreaterEqual(
            self.popup.count("Icons.getProviderWeatherIcon("), 2,
            "both the current-conditions symbol and the forecast cards need the "
            "provider-aware lookup.")

    def test_forecast_cards_never_take_the_night_variant(self):
        """Thursday's card is not about what the sky looks like tonight."""
        cards = re.findall(r"Icons\.getProviderWeatherIcon\(([^)]*)\)", self.popup, re.S)
        night_flags = [call.rsplit(",", 1)[1].strip() for call in cards]
        self.assertIn("false", night_flags,
                      "no call passes a fixed day variant, so a forecast card "
                      "shows tonight's icon for a daytime forecast.")


class WeatherIconLookupTests(unittest.TestCase):
    def test_the_provider_aware_lookup_exists_and_is_not_a_wrapper(self):
        """It has to branch, or it is the WWO table with extra steps."""
        icons = ICONS.read_text(encoding="utf-8")
        self.assertIn("function getProviderWeatherIcon", icons)
        self.assertIn("function getOwmWeatherIcon", icons)
        body = _function_body(icons, "getProviderWeatherIcon")
        self.assertIsNotNone(body)
        self.assertIn("owm", body,
                      "the provider-aware lookup does not branch on the provider.")

    def test_the_forecast_library_stays_free_of_qml(self):
        """`.pragma library` has no QML engine context - no `Qt`, no singletons.

        Reaching for one throws at call time rather than at load time, so the
        forecast would simply stop being populated, with a line in the log and
        a widget that looks like the provider returned nothing.
        """
        source = FORECAST_JS.read_text(encoding="utf-8")
        self.assertTrue(source.lstrip().startswith(".pragma library"))
        code = _without_comments(source)
        self.assertNotRegex(code, r"\bQt\.", "a library JS file cannot use `Qt`.")
        for singleton in ("Appearance", "Config", "Translation", "Icons"):
            self.assertNotIn(
                singleton + ".", code,
                f"weatherForecast.js reaches the {singleton} singleton, which a "
                "`.pragma library` file has no engine context for.")


class LocalDateAcrossTimezonesTests(unittest.TestCase):
    """`localIsoDate` must be local, and only a non-UTC clock can prove it.

    This exists because of a mutation that *survived*. Replacing the function's
    body with `date.toISOString().slice(0, 10)` - the exact bug it is written to
    avoid - left `tst_weather_forecast.qml` fully green, because CI and this
    container both run on UTC, where the two are the same string for every
    instant. The unit test was real but its coverage of this one function was
    ambient, and would have shipped a pin that could never fire.

    Re-running that same file under a far-east and a far-west zone is what makes
    the difference observable: at UTC+14 a local early morning is still the
    previous UTC day, and at UTC-11 a local late evening is already the next one.
    Both are in the test's own fixtures.
    """

    ZONES = ("Pacific/Kiritimati", "Pacific/Niue")   # UTC+14 and UTC-11

    def test_the_forecast_unit_test_passes_east_and_west_of_utc(self):
        runner = _qmltestrunner()
        self.assertIsNotNone(
            runner,
            "qmltestrunner was not found, so this check cannot run - and it must "
            "not pass quietly. run_tests.sh needs the same binary.")
        for zone in self.ZONES:
            with self.subTest(timezone=zone):
                if not Path("/usr/share/zoneinfo", zone).exists():
                    self.fail(f"tzdata has no {zone}; this check needs a real "
                              "non-UTC zone to mean anything.")
                env = dict(os.environ, TZ=zone,
                           QT_QPA_PLATFORM=os.environ.get("QT_QPA_PLATFORM", "offscreen"))
                proc = subprocess.run(
                    [runner,
                     "-import", str(TESTS / "mocks"),
                     "-import", str(TESTS / "imports"),
                     "-input", str(FORECAST_QML_TEST)],
                    env=env, capture_output=True, text=True)
                self.assertEqual(
                    proc.returncode, 0,
                    f"tst_weather_forecast.qml fails under TZ={zone}, so a "
                    "forecast card is labelled with the wrong day for part of "
                    f"every day there.\n{proc.stdout}\n{proc.stderr}")


if __name__ == "__main__":
    unittest.main()
