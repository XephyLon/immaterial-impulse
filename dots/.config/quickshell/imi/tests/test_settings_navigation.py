#!/usr/bin/env python3
"""Static contracts for searchable Settings section navigation."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SETTINGS = ROOT / "modules/imi/settings/SettingsContent.qml"


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
            ["Quick", "Appearance", "Cursor", "Wallpaper & Desktop", "Bar & Dock",
             "Sidebars & Panels", "Notifications", "Lock & Idle", "Capture", "General",
             "Devices & Phone", "Services", "Widgets", "Hyprland", "About"],
        )
        self.assertTrue(all(sections.strip() for name, sections in page_entries if name != "About"))

    def test_tree_uses_existing_page_scroll_contract(self):
        self.assertIn('typeof loader.item.goTo === "function"', self.source)
        for page in ("QuickConfig", "AppearanceConfig", "CursorConfig", "BackgroundConfig",
                     "BarConfig", "SidebarsPanelsConfig", "NotificationsConfig", "LockIdleConfig",
                     "CaptureConfig", "GeneralConfig", "PhoneConfig", "ServicesConfig",
                     "HyprlandConfig"):
            source = (ROOT / f"modules/imi/settings/pages/{page}.qml").read_text(encoding="utf-8")
            self.assertIn("function goTo(term)", source, page)

    def test_section_jumps_animate_on_the_scroll_tier(self):
        """A page's goTo() must not write contentY: ContentPage is a momentum
        StyledFlickable, and momentum (like expressive) disables the
        `Behavior on contentY`, so a direct write snaps the page to the section
        in one frame. StyledFlickable.scrollToY animates on the scroll tier in
        every mode, whole (duration, type and curve from one tier), and every
        user input stops it."""
        flickable = (ROOT / "modules/common/widgets/StyledFlickable.qml").read_text(encoding="utf-8")
        self.assertIn("function scrollToY(y)", flickable)
        anim = re.search(r"NumberAnimation \{\s*id: programmaticScroll(.*?)\n    \}", flickable, re.S)
        self.assertIsNotNone(anim, "no programmaticScroll animation on StyledFlickable")
        for prop in ("duration: Appearance.animation.scroll.duration",
                     "easing.type: Appearance.animation.scroll.type",
                     "easing.bezierCurve: Appearance.animation.scroll.bezierCurve"):
            self.assertIn(prop, anim.group(1), prop)
        self.assertEqual(flickable.count("programmaticScroll.stop()"), 5,
                         "scrollToY itself, the three wheel paths and onMovementStarted each stop the programmatic scroll")
        for page in sorted((ROOT / "modules/imi/settings/pages").glob("*.qml")):
            source = page.read_text(encoding="utf-8")
            if "function goTo(term)" not in source:
                continue
            self.assertNotIn("page.contentY =", source, f"{page.name} writes contentY directly - that snaps under momentum scrolling")
            self.assertIn("page.scrollToY(", source, f"{page.name}'s goTo does not scroll through scrollToY")

    def test_branches_animate_height_opacity_and_arrow(self):
        self.assertIn("id: sectionRevealer", self.source)
        self.assertIn("vertical: true", self.source)
        self.assertIn("Behavior on opacity", self.source)
        self.assertIn("Appearance.animation.elementMoveEnter.duration", self.source)
        self.assertIn("Behavior on rotation", self.source)

    def test_selected_category_has_a_translucent_theme_highlight(self):
        self.assertIn(
            "colBackgroundToggled: CF.ColorUtils.transparentize(\n"
            "                                            Appearance.colors.colPrimary, 0.88)",
            self.source,
        )
        self.assertIn(
            "colBackgroundToggledHover: CF.ColorUtils.transparentize(\n"
            "                                            Appearance.colors.colPrimary, 0.78)",
            self.source,
        )

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
            "Appearance": "AppearanceConfig.qml",
            "Wallpaper & Desktop": "BackgroundConfig.qml",
            "Bar & Dock": "BarConfig.qml",
            "Sidebars & Panels": "SidebarsPanelsConfig.qml",
            "Notifications": "NotificationsConfig.qml",
            "Lock & Idle": "LockIdleConfig.qml",
            "Capture": "CaptureConfig.qml",
            "General": "GeneralConfig.qml",
            "Services": "ServicesConfig.qml",
            # The page file deliberately keeps its Plugin* name; only the
            # user-facing noun became "Widgets".
            "Widgets": "PluginsPage.qml",
            "Hyprland": "HyprlandConfig.qml",
            "About": "About.qml",
        }
        entries = dict(re.findall(
            r'\{ name: Translation\.tr\("([^"]+)"\).*?sections: \[(.*?)\](?:,.*?)? \}',
            self.source,
        ))

        for page_name, filename in pages.items():
            declared = re.findall(r'Translation\.tr\("([^"]+)"\)', entries[page_name])
            page_source = (ROOT / "modules/imi/settings/pages" / filename).read_text(encoding="utf-8")
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


class PageIndexPinTests(unittest.TestCase):
    def test_no_hardcoded_page_indexes(self):
        # `currentPage === 7` went stale when the Plugins page shifted About
        # from 7 to 8 - the About specs then never refreshed on first open.
        content = (ROOT / "modules/imi/settings/SettingsContent.qml").read_text()
        self.assertNotRegex(content, r"currentPage ===? \d")
        self.assertIn("currentPage === pages.length - 1", content)


def braced_block(source, marker):
    """The `{ ... }` block that ENCLOSES `marker`.

    Not the one that follows it: an `id:` line sits inside its own object, and
    a check reading forward from one lands on whichever sub-block happens to be
    declared next - for `id: pageWarmer` that is `onTriggered`, so the interval
    and the `running` gate the check is about are outside what it read.
    """
    marker_at = source.index(marker)
    depth = 0
    for offset in range(marker_at, -1, -1):
        if source[offset] == "}":
            depth += 1
        elif source[offset] == "{":
            if depth == 0:
                break
            depth -= 1
    else:
        raise AssertionError(f"no enclosing block for {marker!r}")
    open_brace, depth = offset, 0
    for offset in range(open_brace, len(source)):
        if source[offset] == "{":
            depth += 1
        elif source[offset] == "}":
            depth -= 1
            if depth == 0:
                return source[open_brace:offset + 1]
    raise AssertionError(f"unterminated block around {marker!r}")


class PageIncubationContractTests(unittest.TestCase):
    """How the settings host builds its pages.

    The host used to assign `active = true` to all fifteen page loaders inside
    one `Qt.callLater` at `Config.ready`, which destroyed the `active:` binding
    declared beside them and built ~24500 items in one turn of the event loop -
    measured at 622ms of frozen GUI thread, paid by the whole shell at startup
    whether or not the window was ever opened. `tests/
    test_settings_page_incubation_runtime.py` drives the behaviour; this is the
    half that runs where there is no compositor.
    """

    @classmethod
    def setUpClass(cls):
        cls.source = SETTINGS.read_text(encoding="utf-8")
        cls.page_loader = braced_block(cls.source, "id: pageLoader")

    def test_no_loop_activates_every_page_loader(self):
        # The exact idiom that was there: walk the repeater, assign `active`.
        # The two dialog loaders in the same file legitimately assign theirs -
        # they carry no binding to destroy - so this is scoped to the page
        # loaders by the names that reach them.
        self.assertNotRegex(self.source, r"pagesRepeater\.itemAt\([^)]*\)[^\n]*\.active\s*=")
        self.assertNotRegex(self.source, r"\bloader\.active\s*=")
        self.assertNotRegex(self.source, r"\bprofileLoader\.active\s*=")

    def test_a_page_is_incubated_across_frames(self):
        self.assertIn("asynchronous: true", self.page_loader)
        profile = braced_block(self.source, "id: profileLoader")
        self.assertIn("asynchronous: true", profile)

    def test_the_keep_alive_term_is_not_the_thing_active_produces(self):
        # `item` is what `active` makes, so reading it from `active`'s own
        # binding closes a circle: `Binding loop detected for property
        # "active"`, and Qt drops the re-evaluation rather than erroring.
        active = re.search(r"\n\s*active:.*?(?=\n\s*\n)", self.page_loader, re.S)
        self.assertIsNotNone(active, "the page loader has no active binding")
        self.assertNotIn("item !== null", active.group(0))
        self.assertIn("built", active.group(0))
        self.assertIn("pageLoader.built = true", self.page_loader)

    def test_the_pane_names_both_states_it_can_be_in(self):
        # A blank pane reads as a broken app whichever reason it is blank for.
        self.assertIn("currentLoader?.status === Loader.Error", self.source)
        self.assertIn("This page failed to load", self.source)
        self.assertIn("currentLoader?.status === Loader.Loading", self.source)
        building = braced_block(self.source, "id: buildingPlaceholder")
        # Gated on a settle, so a page that arrives inside one motion tier does
        # not fade a placeholder in and straight back out.
        self.assertIn("shown: building && buildingSettle.elapsed", building)
        self.assertIn("interval: Appearance.animation.elementMoveFast.duration", building)

    def test_the_warm_up_is_idle_work_that_yields_to_the_user(self):
        warmer = braced_block(self.source, "id: pageWarmer")
        self.assertIn("interval: Appearance.animation.elementMoveFast.duration", warmer)
        # Only while the window is up, never while a navigation is settling,
        # and never two pages at once - the engine incubates in the order it
        # was asked, so a warm-up that queued all fifteen would put the page
        # the user just clicked behind fourteen they did not.
        self.assertIn("GlobalStates.settingsOpen", warmer)
        self.assertIn("!warmHold.running", warmer)
        self.assertIn("status === Loader.Loading", warmer)
        self.assertIn("warmHold.restart()", self.source)


if __name__ == "__main__":
    unittest.main()
