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

    def test_enter_and_exit_are_separate_animations(self):
        """One Behavior with ternary duration/easing re-used the collapse
        parameters on the next expand, so the first open decelerated and every
        one after it accelerated. Two explicit animations, chosen imperatively,
        have no such ordering ambiguity.
        """
        self.assertNotRegex(
            self.src, r"Behavior\s+on\s+implicitHeight",
            "the panel height must not animate through a ternary Behavior")
        self.assertIn("id: expandAnim", self.src)
        self.assertIn("id: collapseAnim", self.src)
        self.assertIn("animateTo", self.src)

    def test_rule3_opacity_paired_on_fast(self):
        self.assertIn("elementMoveFast", self.src)

    def test_rule4_clipped(self):
        self.assertIn("clip: true", self.src)

    def test_rule5_content_stays_measured_and_instantiated(self):
        """Rule 5, but the panel must never be hidden via `visible`.

        Qt propagates visibility to descendants and a ColumnLayout drops
        invisible children, so `visible: false` collapses the content's
        implicit height while closed. The next expand then animates toward a
        stale target and corrects mid-flight - a jolt on every open after the
        first. Zero height plus clip hides it without un-measuring it.
        """
        panel = self.src[self.src.index("id: panel"):]
        self.assertNotRegex(panel, r"(?m)^\s*visible:",
                            "the animated panel must not bind `visible`")
        self.assertIn("clip: true", panel)

    def test_a_panel_created_expanded_still_gets_its_height(self):
        """animateTo() runs only from onExpandedChanged, so a panel *created*
        already expanded never gets a height and renders its content clipped
        to nothing. Reachable whenever a view rebuilds its delegates: filtering
        the Widgets page recreates every card, and the enabled ones come back
        open - their options silently vanished until the switch was toggled.
        """
        panel = self.src[self.src.index("id: panel"):]
        self.assertIn("Component.onCompleted", panel)
        completed = panel[panel.index("Component.onCompleted"):]
        self.assertIn("panel.implicitHeight = panel.targetHeight", completed)

    def test_empty_content_gets_no_inset(self):
        """An expanded panel whose content is empty must occupy nothing.

        targetHeight was contentColumn.implicitHeight + verticalInset
        unconditionally, so a panel that opened onto no content still claimed
        its 20px of padding - a band of dead space under every enabled widget
        exposing no options.
        """
        panel = self.src[self.src.index("id: panel"):]
        self.assertIn("contentColumn.implicitHeight > 0", panel)

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
