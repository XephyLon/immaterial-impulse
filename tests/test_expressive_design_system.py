#!/usr/bin/env python3
"""Structural guarantees for the shared expressive library and widget plugins."""

import json
import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
DESIGN_SYSTEM = ROOT / "modules/common/plugins/designsystem"
PLUGIN_ROOT = ROOT / "modules/common/plugins/bundled"
PLUGIN_DIRS = (
    "nandoroid-clock",
    "nandoroid-at-a-glance",
    "nandoroid-media",
    "nandoroid-system-monitor",
    "nandoroid-weather",
    "nandoroid-currency",
)
EXPECTED_OPTIONS = {
    "nandoroid-clock": {"style", "showDate"},
    "nandoroid-at-a-glance": {
        "showGreeting", "showDate", "showEvents", "showQuote", "alignment", "fontSize"
    },
    "nandoroid-media": {"showLyrics", "useRomaji"},
    "nandoroid-system-monitor": {"vertical"},
    "nandoroid-weather": {"sizeMode"},
    "nandoroid-currency": {"sizeMode", "baseCurrency", "quote1", "quote2", "quote3", "quote4"},
}
EXPECTED_ENTRY_TYPES = {
    "nandoroid-clock": "Expressive.NandoClock",
    "nandoroid-at-a-glance": "Expressive.AtAGlance",
    "nandoroid-media": "Expressive.DesktopMediaWidget",
    "nandoroid-system-monitor": "Expressive.DesktopSystemMonitorWidget",
    "nandoroid-weather": "Expressive.DesktopWeatherWidget",
    "nandoroid-currency": "Expressive.DesktopCurrencyWidget",
}


class ExpressiveDesignSystemTest(unittest.TestCase):
    def test_library_is_not_a_plugin(self):
        self.assertFalse((DESIGN_SYSTEM / "manifest.json").exists())
        self.assertTrue((DESIGN_SYSTEM / "ExpressiveTokens.qml").exists())
        self.assertTrue((DESIGN_SYSTEM / "ComponentRegistry.qml").exists())

    def test_complete_widget_source_is_present(self):
        qml_files = list((DESIGN_SYSTEM / "widgets").rglob("*.qml"))
        self.assertGreaterEqual(len(qml_files), 94)
        weather_icons = list((ROOT / "assets/icons/google-weather").glob("*.svg"))
        self.assertEqual(len(weather_icons), 60)

    def test_nandoroid_scale_compatibility_is_finite(self):
        appearance = (ROOT / "modules/common/Appearance.qml").read_text(encoding="utf-8")
        self.assertIn("readonly property real effectiveScale: 1.0", appearance)

    def test_user_widgets_are_independent_attributed_plugins(self):
        ids = set()
        for directory in PLUGIN_DIRS:
            package = PLUGIN_ROOT / directory
            manifest = json.loads((package / "manifest.json").read_text(encoding="utf-8"))
            self.assertNotIn(manifest["id"], ids)
            ids.add(manifest["id"])
            self.assertTrue(manifest.get("author"))
            self.assertEqual(manifest.get("license"), "AGPL-3.0")
            self.assertTrue(manifest.get("sourceUrl"))
            self.assertTrue(manifest.get("upstreamRevision"))
            self.assertEqual(manifest["desktopWidget"]["component"], "Widget.qml")
            # Imported widgets own their exact Material geometry. A fixed host
            # canvas produces the oversized rectangular blur seen on desktop.
            self.assertNotIn("defaultWidth", manifest)
            self.assertNotIn("defaultHeight", manifest)
            self.assertTrue((package / "Widget.qml").exists())
            option_keys = {option["key"] for option in manifest.get("options", [])}
            self.assertEqual(option_keys, EXPECTED_OPTIONS[directory])

            wrapper = (package / "Widget.qml").read_text(encoding="utf-8")
            self.assertNotIn("target: Config.options", wrapper)
            self.assertIn(EXPECTED_ENTRY_TYPES[directory], wrapper)
            self.assertIn("width: implicitWidth", wrapper)
            self.assertIn("height: implicitHeight", wrapper)
            for option_key in option_keys:
                self.assertIn(f'PluginState.option("{manifest["id"]}", "{option_key}"', wrapper)

    def test_currency_is_startup_safe(self):
        currency = json.loads(
            (PLUGIN_ROOT / "nandoroid-currency" / "manifest.json").read_text(encoding="utf-8")
        )
        self.assertTrue(currency["startupSafe"])
        self.assertNotIn("defaultWidth", currency)
        self.assertNotIn("defaultHeight", currency)
        background = (ROOT / "modules/ii/background/Background.qml").read_text(encoding="utf-8")
        self.assertIn("modelData.startupSafe !== false", background)
        host = (ROOT / "modules/common/plugins/PluginWidget.qml").read_text(encoding="utf-8")
        self.assertRegex(host, r"WallpaperBlurSurface\s*{\s*[^}]*?\bz:\s*0\b")
        self.assertRegex(host, r"id:\s*pluginNode\s*z:\s*1\b")
        currency_widget = (
            DESIGN_SYSTEM / "widgets" / "DesktopCurrencyWidget.qml"
        ).read_text(encoding="utf-8")
        self.assertNotIn("Config.options.appearance.currencyWidget.baseCurrency =", currency_widget)
        self.assertNotIn("Config.options.appearance.currencyWidget.quote", currency_widget)
        self.assertIn("signal baseCurrencyRequested", currency_widget)
        self.assertIn("signal quoteCurrencyRequested", currency_widget)
        self.assertIn("signal sizeModeRequested", currency_widget)

    def test_imported_service_compatibility_is_explicit(self):
        date_time = (ROOT / "services" / "DateTime.qml").read_text(encoding="utf-8")
        for field in ("currentTime", "currentDate", "hours", "minutes", "seconds", "time12h"):
            self.assertRegex(date_time, rf"property\s+\w+\s+{field}\s*:")

        weather = (DESIGN_SYSTEM / "widgets" / "DesktopWeatherWidget.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("Weather.current", weather)
        self.assertNotIn("Weather.todayHigh", weather)
        self.assertNotIn("Weather.todayLow", weather)

    def test_weather_resize_is_visible_and_persisted_by_the_plugin(self):
        weather = (DESIGN_SYSTEM / "widgets" / "DesktopWeatherWidget.qml").read_text(
            encoding="utf-8"
        )
        wrapper = (PLUGIN_ROOT / "nandoroid-weather" / "Widget.qml").read_text(
            encoding="utf-8"
        )
        self.assertIn("signal sizeModeRequested(string value)", weather)
        self.assertIn("root.sizeModeRequested(targetMode)", weather)
        self.assertNotIn("margins: -8 * Appearance.effectiveScale", weather)
        self.assertIn(
            'onSizeModeRequested: value => PluginState.setOption("nandoroid_weather", "sizeMode", value)',
            wrapper,
        )

    def test_plugin_blur_supports_tint_and_widget_regions(self):
        options = (ROOT / "modules/common/plugins/PluginOptions.qml").read_text(encoding="utf-8")
        host = (ROOT / "modules/common/plugins/PluginWidget.qml").read_text(encoding="utf-8")
        node = (ROOT / "modules/common/plugins/PluginNode.qml").read_text(encoding="utf-8")
        monitor = (DESIGN_SYSTEM / "widgets" / "DesktopSystemMonitorWidget.qml").read_text(
            encoding="utf-8"
        )
        wrapper = (PLUGIN_ROOT / "nandoroid-system-monitor" / "Widget.qml").read_text(
            encoding="utf-8"
        )

        config = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
        plugins_page = (ROOT / "modules/ii/settings/pages/PluginsPage.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn('key: "blurTintOpacity"', options)
        self.assertIn("property real blurOpacity: 0.1", config)
        self.assertIn('Translation.tr("Blurred plugin opacity")', plugins_page)
        self.assertIn("Config.options.plugins.blurOpacity", host)
        self.assertIn("pluginNode.blurRegions", host)
        self.assertIn("property bool hasCustomBlurRegions", node)
        self.assertIn("property bool managesBlurTint", node)
        self.assertIn("readonly property var blurRegions", monitor)
        self.assertIn("readonly property var blurRegions: content.blurRegions", wrapper)

        for directory in ("nandoroid-currency", "nandoroid-media", "nandoroid-weather"):
            wrapper_text = (PLUGIN_ROOT / directory / "Widget.qml").read_text(encoding="utf-8")
            self.assertIn("readonly property var blurRegions: content.blurRegions", wrapper_text)
            self.assertIn("readonly property bool managesBlurTint: content.managesBlurTint", wrapper_text)
            self.assertIn("useBlurBackground: PluginState.option", wrapper_text)
            self.assertIn("backgroundOpacity: Config.options.plugins.blurOpacity", wrapper_text)

        currency = (DESIGN_SYSTEM / "widgets" / "DesktopCurrencyWidget.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("anchors.margins: -8 * Appearance.effectiveScale", currency)
        self.assertIn("anchors.margins: 6 * Appearance.effectiveScale", currency)
        self.assertIn("signal verticalRequested(bool value)", monitor)
        self.assertIn("root.verticalRequested(!root.isVertical)", monitor)
        self.assertNotIn("margins: -8 * Appearance.effectiveScale", monitor)
        self.assertIn(
            'onVerticalRequested: value => PluginState.setOption("nandoroid_system_monitor", "vertical", value)',
            wrapper,
        )

        for directory in ("nandoroid-clock", "nandoroid-at-a-glance"):
            wrapper_text = (PLUGIN_ROOT / directory / "Widget.qml").read_text(encoding="utf-8")
            self.assertIn("readonly property var blurRegions: []", wrapper_text)


if __name__ == "__main__":
    unittest.main()
