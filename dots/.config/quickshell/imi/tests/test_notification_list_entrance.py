#!/usr/bin/env python3
"""A notification card built while the list is off screen arrives at rest.

The right sidebar's list drew blank under a footer counting sixteen. Measured
in a nested Hyprland with a probe reading every delegate: a card built while
the sidebar's content was hidden - a notification arriving with the panel
closed, the list restored from file at startup - started its ListView `add`
transition (opacity and scale from 0) and the transition never advanced: after
sixteen arrivals with the panel closed the cards read 0.65/0.87/0.96/0.98/0.99,
after a restart five of seven read exactly 0, and opening the panel changed
none of them. Only a card that took a new notification while open was drawn
again. So the view runs no entrance transition while it is not visible, and
coming on screen settles anything a transition left half way.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
VIEW = ROOT / "modules/common/widgets/NotificationListView.qml"
BASE = ROOT / "modules/common/widgets/StyledListView.qml"


class NotificationListEntranceTests(unittest.TestCase):
    def setUp(self):
        self.view = VIEW.read_text(encoding="utf-8")
        self.base = BASE.read_text(encoding="utf-8")

    def test_the_entrance_runs_only_while_the_view_is_on_screen(self):
        self.assertIn("animateAppearance: root.visible", self.view,
                      "a transition started on a hidden view freezes where it started")
        # The gate has to be the one the base's add transition reads.
        add = re.search(r"add: Transition \{(.*?)\n    \}", self.base, re.S)
        self.assertIsNotNone(add)
        self.assertIn("animateAppearance ?", add.group(1))

    def test_coming_on_screen_settles_a_half_faded_card(self):
        self.assertRegex(self.view, r"onVisibleChanged: \{\s*if \(root\.visible\)\s*Qt\.callLater\(root\.settleDelegates\)")
        settle = re.search(r"function settleDelegates\(\): void \{(.*?)\n    \}", self.view, re.S)
        self.assertIsNotNone(settle)
        body = settle.group(1)
        self.assertIn("card.opacity = 1", body)
        self.assertIn("card.scale = 1", body)
        # Delegates only: the highlight items a ListView makes have no card.
        self.assertIn("blurItem", body)


if __name__ == "__main__":
    unittest.main()
