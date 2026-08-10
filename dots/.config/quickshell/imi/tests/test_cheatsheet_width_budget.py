#!/usr/bin/env python3
"""The cheatsheet's column count has to answer to the screen's width, not only
its height.

`columnCount` picks columns from a *row* budget - how many keybind rows fit
vertically before the card grows past the screen. Columns trade height for
width, so on a display with height to spare but not width it asked for four
columns and the outer two ran off both edges, cut off rather than wrapped.

Width cannot be predicted the way rows can: a column is as wide as its widest
section, which is not known until the text has been shaped. So the cap is
measured and lowered. That makes the loop the thing worth pinning - it must only
ever shrink, and it must stop.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
KEYBINDS = ROOT / "modules/imi/cheatsheet/CheatsheetKeybinds.qml"
CHEATSHEET = ROOT / "modules/imi/cheatsheet/Cheatsheet.qml"


class CheatsheetWidthBudgetTests(unittest.TestCase):
    def setUp(self):
        self.keybinds = KEYBINDS.read_text(encoding="utf-8")
        self.cheatsheet = CHEATSHEET.read_text(encoding="utf-8")

    def test_the_window_hands_down_a_width_budget(self):
        self.assertIn("maxContentWidth:", self.cheatsheet,
                      "Cheatsheet.qml must pass a width budget, or nothing bounds the columns")
        self.assertIn("screen?.width", self.cheatsheet,
                      "the budget has to come from the screen the cheatsheet is on")

    def test_the_column_cap_is_measured_against_that_budget(self):
        self.assertIn("property real maxContentWidth", self.keybinds)
        self.assertIn("property int columnCap", self.keybinds)
        self.assertRegex(
            self.keybinds,
            r"columnCount\(root\.sections, root\.availableRows, root\.columnCap\)",
            "the cap has to reach columnCount, or lowering it changes nothing")

    def test_the_fit_loop_only_shrinks_and_terminates(self):
        body = re.search(r"function fitToWidth\(\)\s*\{(.*?)\n    \}", self.keybinds, re.S)
        self.assertIsNotNone(body, "fitToWidth must exist")
        body = body.group(1)

        # Only ever downward. An increment inside the loop, with implicitWidth
        # feeding back into it, is how this oscillates forever instead of
        # settling.
        self.assertIn("columnCap -= 1", body)
        self.assertNotIn("columnCap += 1", body)
        # And a floor, or a card wider than any single column recurses to zero
        # columns and lays out nothing at all.
        self.assertIn("columnCap <= 1", body)

    def test_a_changed_layout_starts_the_search_again(self):
        # Shrink-only means the cap can never recover on its own: rotate to a
        # wider screen, or change the keybind list, and it would stay at
        # whatever the narrowest case needed.
        for trigger in ("onMaxContentWidthChanged", "onSectionsChanged"):
            self.assertIn(trigger, self.keybinds, f"{trigger} must reset the cap")
        resets = re.findall(r"columnCap = root\.maxColumns", self.keybinds)
        self.assertGreaterEqual(len(resets), 2,
                                "both triggers must reset the cap to the maximum")


if __name__ == "__main__":
    unittest.main()
