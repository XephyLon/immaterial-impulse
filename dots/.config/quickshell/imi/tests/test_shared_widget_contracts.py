#!/usr/bin/env python3
"""Structural guarantees for shared settings controls."""

import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLACEHOLDER = ROOT / "modules/common/widgets/PagePlaceholder.qml"
NOTIFICATION_LIST = ROOT / "modules/imi/sidebarRight/notifications/NotificationList.qml"


class SharedWidgetContractsTest(unittest.TestCase):
    def test_config_switch_leaves_parent_spacing_to_its_container(self):
        source = (ROOT / "modules/common/widgets/ConfigSwitch.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("Layout.bottomMargin", source)

    def test_the_placeholder_shape_is_gated_on_the_tested_fit_rule(self):
        """`tst_placeholder_fit.qml` proves the arithmetic; this proves it is used.

        The widget cannot be instantiated by the QML suite (StyledText assigns
        `font.variableAxes`, which needs Qt 6.7 while the suite runs against the
        distribution Qt), so the decision lives in placeholderFit.js and the
        unit test drives it directly. That test goes vacuous the moment
        PagePlaceholder stops asking it, which nothing else would notice.
        """
        source = PLACEHOLDER.read_text(encoding="utf-8")
        self.assertIn("placeholderFit.js", source,
                      "PagePlaceholder no longer imports the fit rule the unit "
                      "test exercises.")
        self.assertRegex(
            source, r"iconShown:[^\n]*(\n[^\n]*)*?iconFits\(",
            "PagePlaceholder computes `iconShown` without calling iconFits(), "
            "so the tested rule is not what decides whether the shape is drawn.")
        self.assertRegex(
            source, r"id:\s*shapeWidget\s*\n\s*visible:\s*root\.iconShown\b",
            "the shape is not gated on iconShown, so it is drawn outside a page "
            "too short to hold it regardless of what the rule says.")

    def test_the_placeholder_measures_the_children_not_the_column(self):
        """A column's implicitHeight excludes an invisible child.

        Deciding from it would drop the shape, free its height, find there is
        room again, put it back, and oscillate - a relayout loop, which in this
        codebase means a pegged core rather than a wrong pixel.
        """
        source = PLACEHOLDER.read_text(encoding="utf-8")
        call = re.search(r"iconFits\((.*?)\)", source, re.S)
        self.assertIsNotNone(call, "PagePlaceholder should call iconFits()")
        self.assertNotIn("column.implicitHeight", call.group(1),
                         "measuring the column feeds the shape's own visibility "
                         "back into the decision that hides it.")
        self.assertIn("shapeWidget.implicitHeight", call.group(1),
                      "the shape's own implicit height is the term that does not "
                      "move when it is hidden.")

    def test_the_notification_placeholder_opts_in_and_gets_the_lists_area(self):
        """#87: the squeezed page, and the only one that opts in.

        The status row along the bottom is not space the empty state can use,
        so a placeholder filling the whole column would measure room it does
        not have and keep a shape that overlaps the buttons.
        """
        source = NOTIFICATION_LIST.read_text(encoding="utf-8")
        self.assertIn("dropIconWhenCramped: true", source,
                      "the notification list's placeholder no longer opts in, so "
                      "its shape draws outside the container again.")
        self.assertRegex(
            source, r"anchors\.fill:\s*listClip",
            "the placeholder must be given the list's area (listClip since the OpacityMask fix wrapped the view - same rect, clipped), not the whole "
            "column - otherwise it measures the status row's height as free.")


if __name__ == "__main__":
    unittest.main()
