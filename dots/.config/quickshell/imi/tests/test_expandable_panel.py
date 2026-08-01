#!/usr/bin/env python3
"""Source contract for ExpandablePanel.

The QML suite instantiates pure-logic singletons and never builds widgets, so
these are greppable pins on the parts of the Expandable Content contract
(docs/M3_GUIDELINES.md) that fail silently when they regress.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "modules/common/widgets/ExpandablePanel.qml"


class ExpandablePanelContract(unittest.TestCase):
    def setUp(self):
        self.src = PANEL.read_text(encoding="utf-8")

    def test_exists_and_is_a_styled_rectangle(self):
        self.assertTrue(PANEL.exists())
        self.assertRegex(self.src, r"(?m)^StyledRectangle\s*\{")

    def test_public_api(self):
        for decl in ("property bool expanded",
                     "property alias header",
                     "default property alias content",
                     "property int surfaceLayer",
                     "property bool outline",
                     "property bool divider",
                     "property bool shapeMorph",
                     "property bool tonalLift",
                     "property int staggerStep",
                     "property Item staggerTarget",
                     "property bool headerClickable"):
            self.assertIn(decl, self.src, f"missing public property: {decl}")

    def test_component_never_drives_its_own_expanded(self):
        # The trigger belongs to the call site. An internal assignment would
        # make ConfigSwitch-driven and chevron-driven adopters fight it.
        self.assertNotRegex(self.src, r"(?<!property bool )\bexpanded\s*=(?!=)")

    def test_rule2_asymmetric_motion(self):
        self.assertIn("elementMoveEnter.duration", self.src)
        self.assertIn("elementMoveExit.duration", self.src)
        self.assertIn("elementMoveEnter.bezierCurve", self.src)
        self.assertIn("elementMoveExit.bezierCurve", self.src)

    def test_rule3_opacity_paired_on_fast(self):
        self.assertIn("elementMoveFast", self.src)

    def test_rule4_clipped(self):
        self.assertIn("clip: true", self.src)

    def test_rule5_alive_until_zero_height(self):
        self.assertRegex(self.src, r"visible:\s*root\.expanded\s*\|\|\s*implicitHeight\s*>\s*0")

    def test_rule6_indent_is_leading_only(self):
        # Symmetric insets are what PluginsPage did wrong: the trailing edge
        # must stay aligned with the header. Scoped to the animated panel -
        # the divider above it is a full-width rule and is symmetric on
        # purpose.
        panel = self.src[self.src.index("id: panel"):]
        left = re.search(r"Layout\.leftMargin:\s*Appearance\.spacing\.(\w+)", panel)
        right = re.search(r"Layout\.rightMargin:\s*Appearance\.spacing\.(\w+)", panel)
        self.assertIsNotNone(left, "panel declares no leading inset")
        self.assertIsNotNone(right, "panel declares no trailing inset")
        self.assertNotEqual(left.group(1), right.group(1),
                            "leading and trailing insets must differ")

    def test_rule7_collapsed_content_is_disabled(self):
        self.assertIn("enabled: root.expanded", self.src)

    def test_no_raw_durations_or_curves(self):
        body = re.sub(r"//.*", "", self.src)
        self.assertNotRegex(body, r"duration:\s*\d+")
        self.assertNotRegex(body, r"easing\.type:\s*Easing\.(?!BezierSpline)")


if __name__ == "__main__":
    unittest.main()
