#!/usr/bin/env python3
"""Source contract for the Widgets page filter UI.

The QML suite instantiates pure-logic singletons and never builds widgets, so
these are greppable pins on the parts of the Widgets page IA that fail silently
when they regress.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHIP = ROOT / "modules/common/widgets/FilterChip.qml"
STORE = ROOT / "modules/imi/settings/pages/PluginStorePage.qml"
MANAGER = ROOT / "modules/common/plugins/PluginManager.qml"
PAGE = ROOT / "modules/imi/settings/pages/PluginsPage.qml"


class FilterChipIsShared(unittest.TestCase):
    def test_chip_is_a_shared_widget_file(self):
        self.assertTrue(CHIP.exists(),
                        "FilterChip must live in modules/common/widgets")

    def test_chip_is_a_ripple_button(self):
        src = CHIP.read_text(encoding="utf-8")
        self.assertRegex(src, r"(?m)^RippleButton\s*\{")

    def test_chip_exposes_label_and_icon(self):
        src = CHIP.read_text(encoding="utf-8")
        self.assertIn("property string label", src)
        self.assertIn("property string chipIcon", src)

    def test_store_no_longer_declares_a_local_chip(self):
        """A page-local `component FilterChip` is how the chip got trapped in a
        gated-off page in the first place. If it comes back, the two filter
        surfaces can drift apart again.
        """
        src = STORE.read_text(encoding="utf-8")
        self.assertNotRegex(src, r"component\s+FilterChip\s*:",
                            "PluginStorePage must use the shared FilterChip")


class CapabilityVocabulary(unittest.TestCase):
    def setUp(self):
        self.src = MANAGER.read_text(encoding="utf-8")

    def test_manager_owns_the_vocabulary(self):
        self.assertIn("readonly property var surfaceCapabilities", self.src)

    def test_vocabulary_covers_every_surface_in_use(self):
        """overlay-widget is declared by discordVoice but was missing from the
        store's hardcoded list, so that plugin matched no filter at all.
        """
        for value in ("desktop-widget", "bar-widget", "overlay-widget", "panel"):
            self.assertIn(f'"{value}"', self.src,
                          f"surfaceCapabilities is missing {value}")

    def test_settings_is_not_a_surface(self):
        """`settings` means "this plugin has options", not "this plugin draws
        on surface X". It must never become a filter chip.
        """
        block = re.search(r"surfaceCapabilities:\s*\[.*?\]", self.src, re.S)
        self.assertIsNotNone(block, "surfaceCapabilities must be a list literal")
        self.assertNotIn('"settings"', block.group(0))

    def test_manifests_without_capabilities_fall_back_to_desktop_widget(self):
        """clock/manifest.json is the older declarative-JSON generation: it has
        a desktopWidget block and no capabilities array. Without this fallback
        it matches no chip and vanishes from every filtered view.
        """
        self.assertIn("function pluginSurfaces", self.src)
        surfaces = self.src[self.src.index("function pluginSurfaces"):]
        self.assertIn("desktopWidget", surfaces)
        self.assertIn("desktop-widget", surfaces)

    def test_store_reads_the_shared_vocabulary(self):
        store = STORE.read_text(encoding="utf-8")
        self.assertIn("PluginManager.surfaceCapabilities", store)
        self.assertNotRegex(
            store, r"readonly property var capabilityOptions",
            "the store must not keep a second copy of the vocabulary")

    def test_store_still_consumes_the_shared_chip(self):
        """Guards the consumer side of Task 1: deleting the store's FilterChip
        usages or its widgets import would leave the chip tests green while the
        page breaks at runtime, which the QML suite cannot catch.
        """
        store = STORE.read_text(encoding="utf-8")
        self.assertIn("FilterChip {", store)
        self.assertIn("import qs.modules.common.widgets", store)


class WidgetsPageFiltering(unittest.TestCase):
    def setUp(self):
        self.src = PAGE.read_text(encoding="utf-8")

    def test_filter_state_exists(self):
        self.assertIn("property string capabilityFilter", self.src)
        self.assertIn("property bool thirdPartyOnly", self.src)

    def test_filtered_model_is_used_by_the_list(self):
        """The Repeater must render the filtered list, not the raw one."""
        self.assertIn("readonly property var filteredPlugins", self.src)
        self.assertRegex(self.src, r"model:\s*root\.filteredPlugins")

    def test_capability_match_uses_the_shared_helper(self):
        """Re-deriving the surface list here would reintroduce the clock bug."""
        self.assertIn("PluginManager.pluginSurfaces", self.src)

    def test_search_is_case_insensitive_over_name_and_description(self):
        block = self.src[self.src.index("filteredPlugins"):]
        self.assertIn("toLowerCase", block)
        self.assertIn("name", block)
        self.assertIn("description", block)

    def test_third_party_uses_the_same_origin_test_as_the_badge(self):
        self.assertIn('_origin === "installed"', self.src)


if __name__ == "__main__":
    unittest.main()
