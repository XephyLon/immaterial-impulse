#!/usr/bin/env python3
"""An unpainted bar can shade the screen edge behind it, and its border thins with its fill.

With the background off and the groups transparent the bar is glyphs
straight over the wallpaper. `bar.edgeShadow` draws a shade at the screen
edge fading to nothing across the bar - from whichever edge the bar sits on,
the bottom flag being the right-hand side when vertical - in both bar
contents, only in that state, and only when asked; Settings > Bar carries
the switch, inert otherwise. Separately, `colLayer0Border` is thinned by the
background transparency rather than mixed with the thinned fill, so the
plate's border follows the shell opacity slider instead of ringing a
see-through plate.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
CONTENTS = (ROOT / "modules/imi/bar/BarContent.qml", ROOT / "modules/imi/verticalBar/VerticalBarContent.qml")
BAR_CONFIG = ROOT / "modules/imi/settings/pages/BarConfig.qml"
CONFIG = ROOT / "modules/common/Config.qml"
APPEARANCE = ROOT / "modules/common/Appearance.qml"

STYLES = r"\(Config\.options\.bar\.cornerStyle === 0 \|\| Config\.options\.bar\.cornerStyle === 1 \|\| Config\.options\.bar\.cornerStyle === 4\)"
GATE = (r"visible: Config\.options\.bar\.edgeShadow && !Config\.options\.bar\.showBackground\s*&& Config\.options\.bar\.borderless === \"transparent\"\s*&& "
        + STYLES)


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))


class EdgeShadowTests(unittest.TestCase):
    def test_the_option_exists_and_defaults_off(self):
        self.assertRegex(strip_comments(CONFIG.read_text(encoding="utf-8")), r"property bool edgeShadow: false")

    def test_both_bars_draw_it_only_in_the_unpainted_state_from_the_bars_edge(self):
        for path, orientation in zip(CONTENTS, ("Vertical", "Horizontal")):
            text = strip_comments(path.read_text(encoding="utf-8"))
            block = re.search(r"Rectangle \{\s*id: edgeShadow(.*?)\n    \}", text, re.S)
            self.assertIsNotNone(block, f"{path.name} draws the edge shadow")
            body = block.group(1)
            self.assertRegex(body, GATE, f"{path.name}: drawn only with the background off and the groups transparent, when asked")
            self.assertIn(f"orientation: Gradient.{orientation}", body, f"{path.name}: the shade runs across the bar's thickness")
            self.assertRegex(body, r'position: 0; color: Config\.options\.bar\.bottom \? "transparent" : Appearance\.colors\.colBarEdgeShade')
            self.assertRegex(body, r'position: 1; color: Config\.options\.bar\.bottom \? Appearance\.colors\.colBarEdgeShade : "transparent"')
            # Behind the plate, so a painted background (were it ever on) covers it.
            self.assertLess(text.index("id: edgeShadow"), text.index("id: barBackground"))

    def test_the_shade_is_a_token(self):
        appearance = strip_comments(APPEARANCE.read_text(encoding="utf-8"))
        self.assertRegex(appearance, r"property color colBarEdgeShade: ColorUtils\.transparentize\(root\.m3colors\.m3shadow, ")

    def test_the_switch_is_inert_outside_that_state(self):
        text = strip_comments(BAR_CONFIG.read_text(encoding="utf-8"))
        block = re.search(r'ConfigSwitch \{(?=[^}]*Translation\.tr\("Edge shadow"\))(.*?)\n\s{16}\}', text, re.S)
        self.assertIsNotNone(block, "Settings > Bar carries an Edge shadow switch")
        # Live under exactly the shade's own three conditions - never while
        # the Show Background switch above it is greyed out (M3, Islands).
        self.assertRegex(block.group(1), r'enabled: ' + STYLES + r'\s*&& !Config\.options\.bar\.showBackground && Config\.options\.bar\.borderless === "transparent"')
        self.assertRegex(block.group(1), r"checked: Config\.options\.bar\.edgeShadow")


class BorderFollowsTheFillTests(unittest.TestCase):
    def test_the_layer0_border_is_thinned_not_mixed_with_the_thinned_fill(self):
        appearance = strip_comments(APPEARANCE.read_text(encoding="utf-8"))
        self.assertRegex(appearance, r"property color colLayer0Border: ColorUtils\.transparentize\(ColorUtils\.mix\(root\.m3colors\.m3outlineVariant, colLayer0Base, 0\.4\), root\.backgroundTransparency\)")


if __name__ == "__main__":
    unittest.main()
