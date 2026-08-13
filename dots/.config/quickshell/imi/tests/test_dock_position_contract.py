#!/usr/bin/env python3
"""The dock's position derives from one place, and nothing names a side twice.

The dock used to spell its geometry out in four files that had to agree:
Dock.qml's anchors and exclusive zone, and hand-written topMargin/bottomMargin
pairs in the dock body, the separator and the app buttons. Four coordinated
edits is how a mirror drifts - one file gets flipped and the others quietly
keep pointing at the bottom of the screen.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCK = ROOT / "modules/imi/dock/Dock.qml"
GEOMETRY = ROOT / "modules/imi/dock/dock_geometry.js"
CONFIG = ROOT / "modules/common/Config.qml"
DEFAULTS = ROOT / "defaults/config.json"
SETTINGS = ROOT / "modules/imi/settings/pages/BarConfig.qml"
RULES = ROOT.parents[2] / ".config/hypr/hyprland/rules.lua"


class DockPositionContractTest(unittest.TestCase):
    def test_the_dock_reads_its_geometry_rather_than_spelling_it(self):
        source = DOCK.read_text(encoding="utf-8")
        self.assertIn("dock_geometry.js", source)
        for derived in ("DockGeometry.thickness(", "DockGeometry.exclusiveZone(",
                        "DockGeometry.anchors(", "DockGeometry.margins(",
                        "DockGeometry.revealOffsets("):
            self.assertIn(derived, source, f"{derived} is spelled out again")
        # The arithmetic itself may not reappear in the QML.
        self.assertNotIn("anchors { bottom: true; left: true; right: true }", source,
                         "the anchors are literal again")

    def test_the_edge_comes_from_config_and_survives_nonsense(self):
        self.assertIn("property string edge:", CONFIG.read_text(encoding="utf-8"))
        self.assertIn('"edge": "bottom"', DEFAULTS.read_text(encoding="utf-8"))
        source = DOCK.read_text(encoding="utf-8")
        self.assertIn("DockGeometry.normalizedEdge(", source,
                      "a hand-edited config or an old preset must not unanchor the dock")

    def test_the_settings_row_writes_the_string_directly(self):
        source = SETTINGS.read_text(encoding="utf-8")
        self.assertIn('text: Translation.tr("Dock position")', source)
        self.assertIn("Config.options.dock.edge = newValue", source)
        # The whole argument for a new key rather than parity with the bar's
        # overloaded pair is that nothing has to open-code a bitfield.
        row = source[source.index('Translation.tr("Dock position")'):]
        row = row[:row.index("}\n                }")]
        for edge in ('"top"', '"left"', '"bottom"', '"right"'):
            self.assertIn(edge, row)
        self.assertNotIn("& 1", row)
        self.assertNotIn("| 2", row)

    def test_what_follows_the_edge_derives_it_and_does_not_assume_bottom(self):
        for path in (ROOT / "modules/common/widgets/DragApps.qml",
                     ROOT / "modules/common/widgets/DockAppButton.qml",
                     ROOT / "modules/common/widgets/DockContextMenu.qml"):
            source = path.read_text(encoding="utf-8")
            self.assertIn("dock.edge", source,
                          f"{path.name} still assumes which edge the dock is on")

    def test_the_slide_follows_the_surface_rather_than_naming_an_edge(self):
        # `slide bottom` pinned the exit animation to one edge, so a top dock
        # slid downward - into the screen - to leave.
        source = RULES.read_text(encoding="utf-8")
        rule = [line for line in source.splitlines()
                if 'namespace = "quickshell:dock"' in line and "animation" in line]
        self.assertEqual(len(rule), 1, "one animation rule for the dock")
        self.assertIn('animation = "slide"', rule[0])
        self.assertNotIn("slide bottom", rule[0])

    def test_the_geometry_module_has_no_side_names_in_its_arithmetic(self):
        # It maps direction onto side names in exactly one function; anywhere
        # else is a second derivation waiting to disagree with the first.
        source = GEOMETRY.read_text(encoding="utf-8")
        body = source[source.index("function thickness"):]
        for function in ("function thickness", "function exclusiveZone", "function insets",
                         "function revealOffsets"):
            start = body.index(function)
            end = body.index("\n}", start)
            chunk = body[start:end]
            self.assertFalse(re.search(r'"(top|bottom|left|right)"', chunk),
                             f"{function} names a side")


if __name__ == "__main__":
    unittest.main(verbosity=2)
