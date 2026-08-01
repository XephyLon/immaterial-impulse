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
SWITCH = ROOT / "modules/common/widgets/ConfigSwitch.qml"
NAV = ROOT / "modules/imi/settings/SettingsContent.qml"


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

    def test_manager_imports_the_translation_module(self):
        """surfaceCapabilities wraps every label in Translation.tr(), and
        Translation is a qs.services singleton. The import is NOT transitive
        through qs.modules.common: without it each label throws
        ReferenceError, the property stays undefined, and the chip row renders
        no chips at all - with a fully green test suite.
        """
        self.assertIn("import qs.services", self.src)

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

    def _binding_body(self):
        """Just the filteredPlugins binding.

        Slicing to end-of-file instead swallows the ConfigSwitch delegate,
        which already renders modelData.name and modelData.description - so
        assertions about the search reading name/description could never fail.
        """
        start = self.src.index("readonly property var filteredPlugins")
        return self.src[start:self.src.index("\n    }", start)]

    def test_filter_state_exists(self):
        self.assertIn("property string searchQuery", self.src)
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
        """Both sides must be lowercased, and both fields must be searched.

        Mutation-checked: dropping either toLowerCase, searching only the id,
        or deleting the search clause outright must each fail this test.
        """
        body = self._binding_body()
        self.assertEqual(body.count(".toLowerCase()"), 2,
                         "lowercase both the query and the haystack")
        self.assertIn("plugin.name", body)
        self.assertIn("plugin.description", body)
        self.assertIn("haystack.includes(query)", body)

    def test_third_party_filter_excludes_bundled_plugins(self):
        """Pin the filter clause, not just the string.

        Asserting that '_origin === "installed"' appears somewhere in the file
        is vacuous: the third-party badge and the delete button both already
        contain it, so the assertion passed before this filter existed and
        survived inverting the comparison.
        """
        self.assertIn('plugin._origin !== "installed"', self._binding_body())


class WidgetsPageFilterUi(unittest.TestCase):
    def setUp(self):
        self.src = PAGE.read_text(encoding="utf-8")

    def test_search_field_is_bound_to_the_query(self):
        """ConfigTextArea.text is the *label*; the typed value is `.value`.
        Binding the wrong one silently produces a search box that never
        filters anything.

        Anchored on `searchQuery` itself: a bare `onValueChanged` also matches
        the blur-opacity ConfigSlider on this page, so it would never fail.
        """
        self.assertRegex(self.src, r"searchQuery:\s*Qt\.binding|searchQuery\s*=\s*\w+\.value")

    def test_chips_come_from_the_shared_vocabulary(self):
        self.assertRegex(self.src, r"model:\s*PluginManager\.surfaceCapabilities")

    def test_chip_click_clears_when_already_active(self):
        self.assertIn('capabilityFilter === modelData.value ? "" : modelData.value',
                      self.src)

    def test_search_handler_is_wired_to_the_right_field(self):
        """`onValueChanged` -> `onTextChanged` is the exact "search box never
        filters" bug, and wiring it to `manifestUrl.value` would search the
        install-from-URL field instead. Both mutations survive a regex that
        only anchors on the assignment.
        """
        self.assertRegex(
            self.src,
            r"onValueChanged:\s*root\.searchQuery\s*=\s*searchField\.value")

    def test_capability_chips_reflect_the_active_filter(self):
        """`toggled: false` renders every chip permanently inactive while
        filtering still works - the user sees no selection and cannot tell
        which filter is on.
        """
        self.assertIn("toggled: root.capabilityFilter === modelData.value",
                      self.src)
        self.assertIn("label: modelData.label", self.src)
        self.assertIn("chipIcon: modelData.icon", self.src)

    def test_third_party_chip_is_present_and_wired(self):
        """Deleting this chip leaves thirdPartyOnly unreachable from the UI
        with the rest of the suite green.
        """
        self.assertIn("toggled: root.thirdPartyOnly", self.src)
        self.assertIn('chipIcon: "extension"', self.src)

    def test_empty_state_distinguishes_no_widgets_from_no_matches(self):
        """An empty list is not proof a filter excluded something.
        availablePlugins starts empty and fills in asynchronously, so a single
        message would blame a filter the user never set.
        """
        self.assertRegex(self.src, r"filteredPlugins\.length === 0")
        self.assertIn("PluginManager.availablePlugins.length === 0", self.src)


class SettingsLabelsArePlainText(unittest.TestCase):
    def test_config_switch_renders_both_strings_as_plain_text(self):
        """ConfigSwitch renders its label and description through StyledText,
        which has no textFormat and so inherits Text.AutoText - Qt auto-detects
        and renders rich text. Plugin manifests are attacker-controlled, so a
        manifest name of "<img src=...>" would render as markup.
        """
        src = SWITCH.read_text(encoding="utf-8")
        # Asserted per-block rather than as an exact count of 2: counting
        # fails when a *third* element in this file is legitimately hardened,
        # which would penalise the more secure change and pressure someone
        # into weakening the assertion.
        for binding in ("text: root.text", "text: root.description"):
            start = src.index(binding)
            end = src.find("StyledText {", start)
            block = src[start:end if end != -1 else len(src)]
            self.assertIn("textFormat: Text.PlainText", block,
                          f"`{binding}` renders without PlainText")

    def test_page_still_feeds_manifest_strings_through_config_switch(self):
        """Pins why the fix lives in ConfigSwitch rather than on the page: if
        the page ever renders manifest strings directly, this test's premise is
        stale and the new render site needs its own textFormat.
        """
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn("text: modelData.name", page)
        # An optional id prefix matters: this page's delegate writes
        # `pluginCard.modelData.name`, so a pattern requiring `modelData`
        # immediately after `text:` would miss the single most likely form of
        # the regression it exists to catch.
        self.assertNotRegex(
            page,
            r"StyledText\s*\{[^}]*text:\s*[\w.]*modelData\.(name|description)",
            "the page renders a manifest string directly - harden it too")

    def test_material_symbol_renders_icon_names_as_plain_text(self):
        """ConfigSwitch's own buttonIcon is an injection path.

        buttonIcon -> OptionalMaterialSymbol -> MaterialSymbol, and
        MaterialSymbol is itself a StyledText. PluginOptions feeds it
        `optionData.icon` straight from the manifest, so an option icon of
        "<img src=...>" rendered as markup inside the very widget the
        PlainText fix was meant to close. Icon ligature names are never rich
        text, so pinning this globally is safe.
        """
        symbol = (ROOT / "modules/common/widgets/MaterialSymbol.qml").read_text(
            encoding="utf-8")
        self.assertIn("textFormat: Text.PlainText", symbol)


class UserFacingRename(unittest.TestCase):
    def test_nav_entry_says_widgets(self):
        src = NAV.read_text(encoding="utf-8")
        self.assertIn('Translation.tr("Widgets")', src)
        self.assertIn('Translation.tr("Available Widgets")', src)

    def test_nav_entry_still_points_at_the_unrenamed_page_file(self):
        """Types, files and config keys deliberately keep their Plugin* names;
        renaming them would break every existing install for no user benefit.
        """
        src = NAV.read_text(encoding="utf-8")
        self.assertIn("pages/PluginsPage.qml", src)

    def test_config_key_is_untouched(self):
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn("Config.options.plugins", page)


if __name__ == "__main__":
    unittest.main()
