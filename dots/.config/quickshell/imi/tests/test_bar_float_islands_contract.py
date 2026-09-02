#!/usr/bin/env python3
"""Bar style 4, Float Islands: M3's three sections, each drawn as Float's plate.

The shape is decided in more than one file, and every place that keys on
"is this a float style" has to know about the fifth value, or the new style
inherits some other style's numbers: Float's thickness and exclusive zone,
the sidebars' top margin, the media popup's gap, the settings selectors and
the switches they enable. This pins each site, and the islands themselves -
three plates in Float's look behind the populated sections, handed to the
blur region like the M3 wrappers are.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


FLOATS = "Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 4"


class FloatIslandsContractTests(unittest.TestCase):
    def test_the_config_names_the_style(self):
        self.assertIn("4: Float Islands", source("modules/common/Config.qml"))

    def test_both_bars_draw_three_islands_behind_populated_sections(self):
        for rel, sections in (("modules/imi/bar/BarContent.qml", ("left", "center", "right")),
                              ("modules/imi/verticalBar/VerticalBarContent.qml", ("top", "center", "bottom"))):
            text = source(rel)
            self.assertIn("readonly property bool isFloatIslands: Config.options.bar.cornerStyle === 4", text, rel)
            self.assertIn("component Island: Rectangle {", text, rel)
            island = text.split("component Island: Rectangle {", 1)[1].split("component IslandShadow", 1)[0]
            self.assertIn("radius: Appearance.rounding.windowRounding", island, rel)
            self.assertIn("border.color: Appearance.colors.colLayer0Border", island, rel)
            self.assertIn("!root.centerOnly && populated", island, rel)
            for name in sections:
                self.assertIn(f"id: {name}Island", text, f"{rel}: {name}")
                self.assertIn(f"readonly property bool {name}IslandPainted: {name}Island.visible", text, f"{rel}: {name}")
            # The full-width plate stands down for the islands.
            self.assertIn("&& !root.isFloatIslands", text.split("readonly property bool backgroundPainted", 1)[1].split("\n\n", 1)[0], rel)

    def test_the_blur_region_covers_the_islands(self):
        for rel, sections in (("modules/imi/bar/Bar.qml", ("left", "center", "right")),
                              ("modules/imi/verticalBar/VerticalBar.qml", ("top", "center", "bottom"))):
            text = source(rel)
            for name in sections:
                self.assertRegex(text, rf"item: barContent\.{name}IslandPainted \? barContent\.{name}IslandItem : null\s*\n\s*radius: barContent\.{name}IslandItem\.radius", f"{rel}: {name}")

    def test_the_thickness_and_zone_are_floats(self):
        appearance = source("modules/common/Appearance.qml")
        self.assertRegex(appearance, r"property real barHeight: \(" + re.escape(FLOATS) + r"\)")
        self.assertRegex(appearance, r"property real verticalBarWidth: \(" + re.escape(FLOATS) + r"\)")
        self.assertIn("(" + FLOATS + ") ? Appearance.sizes.hyprlandGapsOut : 0", source("modules/imi/bar/Bar.qml"))
        self.assertIn("(" + FLOATS + ") ? Appearance.sizes.hyprlandGapsOut : 0", source("modules/imi/verticalBar/VerticalBar.qml"))

    def test_the_surfaces_that_key_on_float_know_the_fifth_value(self):
        for rel in ("modules/imi/sidebarRight/SidebarRight.qml", "modules/imi/sidebarLeft/SidebarLeft.qml"):
            self.assertIn("case 4: return -Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut;", source(rel), rel)
        self.assertIn("Config.options.bar.cornerStyle === 4", source("modules/imi/mediaControls/MediaControls.qml").split("cornerStyleReducesGap:", 1)[1].split("\n", 1)[0])

    def test_both_selectors_offer_it_and_the_float_switches_admit_it(self):
        for rel in ("modules/imi/settings/pages/BarConfig.qml", "modules/imi/settings/pages/QuickConfig.qml"):
            self.assertIn('{ displayName: Translation.tr("Float Islands"), icon: "view_week", value: 4 }', source(rel), rel)
        bar = source("modules/imi/settings/pages/BarConfig.qml")
        self.assertEqual(bar.count("Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 4"), 2,
                         "Show Background and Bar shadow are the two switches a float plate earns")

    def test_the_geometry_unit_test_sweeps_the_style(self):
        self.assertIn("readonly property var cornerStyles: [0, 1, 2, 3, 4]", source("tests/tst_bar_geometry.qml"))


if __name__ == "__main__":
    unittest.main()
