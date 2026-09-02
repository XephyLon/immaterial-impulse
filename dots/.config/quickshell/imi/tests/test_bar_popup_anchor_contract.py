#!/usr/bin/env python3
"""A bar widget's popup marks its anchor with the dashed outline, and nothing else.

The bar had no open state for a widget whose popup is up, and the one that was
tried - a tonal container behind the widget while toggled - broke every bar
style but M3: a filled pill behind the Docker gauge's bare ring. The open
state is `PopupAnchorOutline`, a dashed primary outline in the widget's own
rounding that fades in and out and marches its dashes on the way; a widget
that owns a click-toggled popup mounts one and binds `shown` to the popup's
open state, and it carries no tonal toggled colours for that state.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
BAR = ROOT / "modules/imi/bar"
OUTLINE = ROOT / "modules/common/widgets/PopupAnchorOutline.qml"

# The widgets whose popup a click holds open, and the state that says so.
POPUP_OWNERS = {
    "DockerPlugin.qml": "root.popupOpen",
    "DiscordVoicePlugin.qml": "root.popupOpen",
    "SysTray.qml": "root.trayOverflowOpen",
}


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))


class PopupAnchorOutlineTests(unittest.TestCase):
    def setUp(self):
        self.outline = strip_comments(OUTLINE.read_text(encoding="utf-8"))

    def test_it_is_geometry_not_a_canvas(self):
        self.assertIn("import QtQuick.Shapes", self.outline)
        self.assertIn("ShapePath {", self.outline)
        self.assertNotIn("Canvas", self.outline, "a Canvas is a GUI-thread raster on every frame the dashes move")

    def test_it_fades_and_marches_on_tokenised_tiers_only(self):
        self.assertNotRegex(self.outline, r"duration:\s*\d", "no literal duration; bind to a tokenised tier")
        self.assertRegex(self.outline, r"Behavior on presence \{\s*animation: Appearance\.animation\.\w+\.numberAnimation\.createObject\(this\)")
        self.assertRegex(self.outline, r"Behavior on march \{\s*animation: Appearance\.animation\.\w+\.numberAnimation\.createObject\(this\)")
        self.assertRegex(self.outline, r"opacity:\s*root\.presence")
        self.assertRegex(self.outline, r"visible:\s*root\.presence > 0")
        self.assertRegex(self.outline, r"dashOffset:.*root\.march")

    def test_its_dashes_tile_the_perimeter_in_whole_counts(self):
        self.assertIn("patternRepeats", self.outline)
        self.assertRegex(self.outline, r"Math\.round\(root\.perimeter / root\.patternLength\)")

    def test_its_lengths_are_tokens(self):
        for prop, token in (("strokeWidth", "Appearance.borderWidth."), ("dashLength", "Appearance.spacing."),
                            ("gapLength", "Appearance.spacing."), ("color", "Appearance.colors.colPrimary")):
            self.assertRegex(self.outline, r"property \w+ " + prop + r": " + re.escape(token))


class PopupOwnerTests(unittest.TestCase):
    def test_every_popup_owner_mounts_the_outline_on_its_open_state(self):
        for name, state in POPUP_OWNERS.items():
            text = strip_comments((BAR / name).read_text(encoding="utf-8"))
            block = re.search(r"PopupAnchorOutline \{(.*?)\n\s*\}", text, re.S)
            self.assertIsNotNone(block, f"{name} owns a popup and must mount PopupAnchorOutline")
            self.assertRegex(block.group(1), r"shown:\s*" + re.escape(state), f"{name}: the outline follows {state}")

    def test_no_popup_owner_paints_a_tonal_container_for_the_open_state(self):
        for name in POPUP_OWNERS:
            text = strip_comments((BAR / name).read_text(encoding="utf-8"))
            for prop in ("colBackgroundToggled", "colBackgroundToggledHover", "colRippleToggled"):
                self.assertNotIn(prop, text, f"{name}: a tonal toggled container is not the open state")

    def test_every_bar_file_with_a_click_held_popup_is_in_the_register(self):
        # A new widget that holds a popup open on a click joins POPUP_OWNERS,
        # or it ships without the open state.
        for path in sorted(BAR.glob("*.qml")):
            text = strip_comments(path.read_text(encoding="utf-8"))
            if re.search(r"property bool popupOpen\b", text) or "trayOverflowOpen" in text:
                self.assertIn(path.name, POPUP_OWNERS, f"{path.name} holds a popup open on a click; register it")


if __name__ == "__main__":
    unittest.main()
