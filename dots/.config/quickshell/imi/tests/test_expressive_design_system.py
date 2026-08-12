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
    "nandoroid-media",
    "nandoroid-system-monitor",
    "nandoroid-weather",
    "nandoroid-currency",
)
EXPECTED_OPTIONS = {
    "nandoroid-media": {"showLyrics", "useRomaji"},
    "nandoroid-system-monitor": {"vertical", "showBattery"},
    # Both widgets declared a `sizeMode` choice option until the host's
    # `__gridSize` took the concept over; their spans are `grid.sizes` now.
    "nandoroid-weather": set(),
    "nandoroid-currency": {"baseCurrency", "quote1", "quote2", "quote3", "quote4"},
}
EXPECTED_ENTRY_TYPES = {
    "nandoroid-media": "Expressive.DesktopMediaWidget",
    "nandoroid-system-monitor": "Expressive.DesktopSystemMonitorWidget",
    "nandoroid-weather": "Expressive.DesktopWeatherWidget",
    "nandoroid-currency": "Expressive.DesktopCurrencyWidget",
}
# Which file in a package instantiates the design-system component. It is the
# package's entry point for all four again: media's per-span layout files -
# which once held everything this module pins about a wrapper - collapsed back
# into Widget.qml when it became the one tree, and the design-system component
# it instantiates (chromeless, for the text and lyrics page) lives there too.
ENTRY_FILES = {}
# ...and the size assertion below moved with it, to the other side: a widget
# whose manifest declares a grid is sized by the host to the span it resolved,
# so its wrapper names spans rather than forwarding a content size.
SIZED_BY_THE_HOST_GRID = {"nandoroid-media", "nandoroid-weather"}


def entry_file(directory):
    return PLUGIN_ROOT / directory / ENTRY_FILES.get(directory, "Widget.qml")


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
            entry = entry_file(directory).read_text(encoding="utf-8")
            self.assertNotIn("target: Config.options", wrapper)
            self.assertNotIn("target: Config.options", entry)
            self.assertIn(EXPECTED_ENTRY_TYPES[directory], entry)
            if directory in SIZED_BY_THE_HOST_GRID:
                self.assertIn("Appearance.sizes.widgetGridSpanX(", wrapper)
                self.assertIn("Appearance.sizes.widgetGridSpanY(", wrapper)
            else:
                self.assertIn("width: implicitWidth", wrapper)
                self.assertIn("height: implicitHeight", wrapper)
            for option_key in option_keys:
                self.assertIn(f'PluginState.option("{manifest["id"]}", "{option_key}"', entry)

    def test_the_media_tree_answers_the_blur_contract_itself(self):
        """One tree, one card, one region list.

        The wrapper used to forward `blurRegions`/`managesBlurTint` off
        whichever layout file its Loader held, and this test made every layout
        answer. The one tree ended the dispatch: the card is a shared element,
        so the tree declares the contract directly from it, and a span change
        cannot swap in a layout that forgot - there is nothing left to swap.
        """
        package = PLUGIN_ROOT / "nandoroid-media"
        wrapper = (package / "Widget.qml").read_text(encoding="utf-8")
        self.assertIn("blurRegions: [bgCard.blurRegion]", wrapper)
        self.assertIn("managesBlurTint: true", wrapper)
        self.assertNotIn("layout.item", wrapper,
                         "the per-span Loader dispatch must not return")
        for dead in ("LayoutLarge.qml", "LayoutCookie.qml", "LayoutCompact.qml"):
            self.assertFalse((package / dead).exists(),
                             f"{dead} is the destroy the tree replaced")

    def test_system_monitor_third_card_can_show_the_battery(self):
        """The built-in this widget replaced showed Battery on a laptop.

        The port was always Disk, so laptops silently lost the reading in the
        dedup. The decision belongs to the wrapper (the design system's entry
        component keeps its upstream default), and the third card's three
        readings - fill level, percentage, label - must all follow the same
        flag or the card renders a battery icon over a disk number.
        """
        package = PLUGIN_ROOT / "nandoroid-system-monitor"
        monitor = (DESIGN_SYSTEM / "widgets" / "DesktopSystemMonitorWidget.qml").read_text(
            encoding="utf-8"
        )
        wrapper = (package / "Widget.qml").read_text(encoding="utf-8")
        helper = (package / "ThirdCard.js").read_text(encoding="utf-8")

        self.assertIn("property bool showBattery: false", monitor,
                      "the injected flag must default to the upstream rendering")
        self.assertIn("Battery.percentage", monitor)
        for binding in ("root.thirdCardLevel", "root.thirdCardIcon", "root.thirdCardLabel"):
            self.assertIn(binding, monitor,
                          f"the third card must read {binding}, not a disk-only expression")
        level = re.search(
            r"readonly property real thirdCardLevel:.*?(?=\n\s*readonly property string)",
            monitor, re.S)
        self.assertIsNotNone(level, "the third card needs one shared level expression")
        self.assertIn("SystemData.diskStats", level.group(0))
        self.assertEqual(
            monitor.count("SystemData.diskStats"),
            level.group(0).count("SystemData.diskStats"),
            "the disk reading must not survive anywhere but the level expression, "
            "or the battery branch renders a battery icon over a disk number",
        )

        self.assertIn("function showsBattery(", helper)
        self.assertIn("import qs.services", wrapper,
                      "Battery is not transitive through qs.modules.common")
        self.assertIn("Battery.available", wrapper,
                      "availability, not the option alone, gates the battery card")
        self.assertIn("ThirdCard.showsBattery(", wrapper)

    def test_currency_is_startup_safe(self):
        currency = json.loads(
            (PLUGIN_ROOT / "nandoroid-currency" / "manifest.json").read_text(encoding="utf-8")
        )
        self.assertTrue(currency["startupSafe"])
        self.assertNotIn("defaultWidth", currency)
        self.assertNotIn("defaultHeight", currency)
        background = (ROOT / "modules/imi/background/Background.qml").read_text(encoding="utf-8")
        self.assertIn("modelData.startupSafe !== false", background)
        host = (ROOT / "modules/common/plugins/PluginWidget.qml").read_text(encoding="utf-8")
        # The node renders above the frost (z 1). The z moved from the node
        # itself to nodeLayerFrame - the padded wrapper carrying the bounded
        # layer, sized with room for the resize bow - so the contract is that
        # the frame is z 1 and the node lives inside it.
        self.assertRegex(host, r"id:\s*nodeLayerFrame\s*z:\s*1\b")
        frame_index = host.index("id: nodeLayerFrame")
        node_index = host.index("id: pluginNode")
        self.assertLess(frame_index, node_index,
                        "the node must sit inside the layered frame")
        currency_widget = (
            DESIGN_SYSTEM / "widgets" / "DesktopCurrencyWidget.qml"
        ).read_text(encoding="utf-8")
        self.assertNotIn("Config.options.appearance.currencyWidget.baseCurrency =", currency_widget)
        self.assertNotIn("Config.options.appearance.currencyWidget.quote", currency_widget)
        self.assertIn("signal baseCurrencyRequested", currency_widget)
        self.assertIn("signal quoteCurrencyRequested", currency_widget)

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

    def test_weather_and_currency_resize_through_the_host_not_their_own_grip(self):
        """Both widgets used to draw a `swap_horiz` grip in their bottom-right
        corner, writing a plugin-declared `sizeMode` option. The host now draws
        its own grip in that exact corner for any manifest offering several
        spans, so keeping theirs would stack two controls on one spot - and
        theirs gated on a legacy `cfg.locked` rather than the host's resolved
        lock, so it stayed live on a pinned widget.
        """
        for directory, component, default in (
                ("nandoroid-weather", "DesktopWeatherWidget", "3x1"),
                ("nandoroid-currency", "DesktopCurrencyWidget", "2x1")):
            widget = (DESIGN_SYSTEM / "widgets" / f"{component}.qml").read_text(
                encoding="utf-8")
            wrapper = (PLUGIN_ROOT / directory / "Widget.qml").read_text(
                encoding="utf-8")
            manifest = json.loads(
                (PLUGIN_ROOT / directory / "manifest.json").read_text(encoding="utf-8"))

            self.assertNotIn("sizeModeRequested", widget,
                             f"{component} still asks to change its own size")
            self.assertNotIn("id: resizeHandle", widget,
                             f"{component} still draws a second resize grip")
            self.assertNotIn('"sizeMode"', wrapper,
                             f"{directory} still reads the retired option "
                             "out of PluginState")

            # The host owns which size; the widget owns what that size looks
            # like, which is why the span still arrives as a name.
            self.assertIn(f'sizeMode: root.hostGridSize || "{default}"', wrapper)
            self.assertIn("property string hostGridSize", wrapper)

            # ...and the manifest is where the spans on offer are declared now.
            self.assertNotIn(
                "sizeMode",
                json.dumps(manifest.get("options", []) or []),
                f"{directory} still declares a sizeMode option")
            self.assertGreater(len(manifest["grid"]["sizes"]), 1,
                               f"{directory} must offer the spans it has layouts for")

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
        plugins_page = (ROOT / "modules/imi/settings/pages/PluginsPage.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn('key: "blurTintOpacity"', options)
        self.assertIn("property real blurOpacity: 0.1", config)
        self.assertIn('Translation.tr("Blurred widget opacity")', plugins_page)
        self.assertIn("property bool hasCustomBlurRegions", node)
        self.assertIn("property bool managesBlurTint", node)
        self.assertIn("readonly property var blurRegions", monitor)
        self.assertIn("readonly property var blurRegions: content.blurRegions", wrapper)

        # Currency and weather forward the contract from the design-system
        # component they wrap; media's one tree owns a card of its own and
        # declares the contract directly from it (see
        # test_the_media_tree_answers_the_blur_contract_itself).
        for directory in ("nandoroid-currency", "nandoroid-weather"):
            entry_text = entry_file(directory).read_text(encoding="utf-8")
            self.assertIn("readonly property var blurRegions: content.blurRegions", entry_text)
            self.assertIn("readonly property bool managesBlurTint: content.managesBlurTint", entry_text)
            self.assertIn("useBlurBackground: PluginState.option", entry_text)
            self.assertIn("backgroundOpacity: PluginState.effectiveBackgroundOpacity(", entry_text)
        media = entry_file("nandoroid-media").read_text(encoding="utf-8")
        self.assertIn('useBlurBackground: PluginState.option("nandoroid_media", "blurEnabled"', media)
        self.assertIn("backgroundOpacity: PluginState.effectiveBackgroundOpacity(", media)

        currency = (DESIGN_SYSTEM / "widgets" / "DesktopCurrencyWidget.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("anchors.margins: -8 * Appearance.effectiveScale", currency)
        self.assertIn("signal verticalRequested(bool value)", monitor)
        self.assertIn("root.verticalRequested(!root.isVertical)", monitor)
        self.assertNotIn("margins: -8 * Appearance.effectiveScale", monitor)
        self.assertIn(
            'onVerticalRequested: value => PluginState.setOption("nandoroid_system_monitor", "vertical", value)',
            wrapper,
        )


if __name__ == "__main__":
    unittest.main()
