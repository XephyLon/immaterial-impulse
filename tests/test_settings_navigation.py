#!/usr/bin/env python3
"""Static contracts for searchable Settings section navigation."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SETTINGS = ROOT / "modules/ii/settings/SettingsContent.qml"


class SettingsNavigationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SETTINGS.read_text(encoding="utf-8")

    def test_top_search_supports_keyboard_and_click_navigation(self):
        self.assertIn('id: settingsSearchField', self.source)
        self.assertIn('sequence: StandardKey.Find', self.source)
        self.assertIn('function navigateFirstMatch()', self.source)
        self.assertIn('Keys.onReturnPressed: root.navigateFirstMatch()', self.source)
        self.assertIn('onClicked: root.navigateTo(pageBranch.index, modelData)', self.source)

    def test_every_page_declares_tree_sections(self):
        page_entries = re.findall(
            r'\{ name: Translation\.tr\("([^"]+)"\).*?sections: \[(.*?)\] \}',
            self.source,
        )
        self.assertEqual(
            [name for name, _ in page_entries],
            ["Quick", "General", "Bar", "Desktop", "Plugins", "Interface", "Services", "Hyprland", "About"],
        )
        self.assertTrue(all(sections.strip() for name, sections in page_entries if name != "About"))

    def test_tree_uses_existing_page_scroll_contract(self):
        self.assertIn('typeof loader.item.goTo === "function"', self.source)
        for page in ("QuickConfig", "GeneralConfig", "BarConfig", "BackgroundConfig", "InterfaceConfig", "ServicesConfig", "HyprlandConfig"):
            source = (ROOT / f"modules/ii/settings/pages/{page}.qml").read_text(encoding="utf-8")
            self.assertIn("function goTo(term)", source, page)

    def test_branches_animate_height_opacity_and_arrow(self):
        self.assertIn("id: sectionRevealer", self.source)
        self.assertIn("vertical: true", self.source)
        self.assertIn("Behavior on opacity", self.source)
        self.assertIn("Appearance.animation.elementMoveEnter.duration", self.source)
        self.assertIn("Behavior on rotation", self.source)

    def test_tree_tracks_the_section_visible_in_the_active_page(self):
        content_page = (ROOT / "modules/common/widgets/ContentPage.qml").read_text(encoding="utf-8")
        content_section = (ROOT / "modules/common/widgets/ContentSection.qml").read_text(encoding="utf-8")
        self.assertIn('property string currentSection: ""', content_page)
        self.assertIn("function navigationSections(item)", content_page)
        self.assertIn("settingsNavigationSection: true", content_section)
        self.assertIn("onContentYChanged: updateCurrentSection()", content_page)
        self.assertIn("function onCurrentSectionChanged()", self.source)
        self.assertIn("root.sectionIsActive(pageBranch.index, modelData)", self.source)
        self.assertIn("if (active.length === 0 || candidate.length === 0) return false", self.source)

    def test_hardware_dependent_sections_follow_runtime_availability(self):
        content_page = (ROOT / "modules/common/widgets/ContentPage.qml").read_text(encoding="utf-8")
        self.assertIn("property var availableSections: []", content_page)
        self.assertIn("nextAvailableSections.push(child.title)", content_page)
        self.assertIn("function sectionAvailable(pageIndex, section)", self.source)
        self.assertIn("loader.item.availableSections", self.source)
        self.assertIn("if (available.length === 0) return true", self.source)
        self.assertIn("root.sectionMatches(pageBranch.index, modelData)", self.source)

    def test_tree_metadata_matches_real_top_level_sections(self):
        pages = {
            "Quick": "QuickConfig.qml",
            "General": "GeneralConfig.qml",
            "Bar": "BarConfig.qml",
            "Desktop": "BackgroundConfig.qml",
            "Plugins": "PluginsPage.qml",
            "Interface": "InterfaceConfig.qml",
            "Services": "ServicesConfig.qml",
            "Hyprland": "HyprlandConfig.qml",
            "About": "About.qml",
        }
        entries = dict(re.findall(
            r'\{ name: Translation\.tr\("([^"]+)"\).*?sections: \[(.*?)\](?:,.*?)? \}',
            self.source,
        ))

        for page_name, filename in pages.items():
            declared = re.findall(r'Translation\.tr\("([^"]+)"\)', entries[page_name])
            page_source = (ROOT / "modules/ii/settings/pages" / filename).read_text(encoding="utf-8")
            actual = []
            for match in re.finditer(r'\bContentSection\s*\{', page_source):
                title = re.search(
                    r'title:\s*Translation\.tr\("([^"]+)"\)',
                    page_source[match.start():match.start() + 400],
                )
                if title:
                    actual.append(title.group(1))

            def corresponds(left, right):
                left, right = left.casefold(), right.casefold()
                return left == right or left in right or right in left

            self.assertTrue(
                all(any(corresponds(item, real) for real in actual) for item in declared),
                f"{page_name} tree contains a section absent from {filename}: {declared} vs {actual}",
            )
            self.assertTrue(
                all(any(corresponds(real, item) for item in declared) for real in actual),
                f"{page_name} omits a section from {filename}: {declared} vs {actual}",
            )


if __name__ == "__main__":
    unittest.main()
