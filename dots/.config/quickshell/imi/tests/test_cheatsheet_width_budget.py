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


PERIODIC = ROOT / "modules/imi/cheatsheet/CheatsheetPeriodicTable.qml"


class CheatsheetHeightBudgetTests(unittest.TestCase):
    """The height budget reads the screen the compositor leaves, not a guess.

    The window is fixed-size (equal min/max hints float and centre it) and as
    tall as its tallest page, so a page that ignores the budget sizes the whole
    window. The keybinds page had a budget of `screen.height - 220` - a number
    standing in for "the bar, the dock and the chrome" on one machine - and the
    Elements page had none at all: 9 rows of 70px tiles on every screen, which
    on a 1080p laptop at 1.25x (864 logical) sat 17px under the bar and 17px
    under the dock, and at 1.5x (720) ran off both edges. Measured in a nested
    Hyprland; the arithmetic is tst_cheatsheet_fit.qml's, this pins the wiring.
    """

    def setUp(self):
        self.cheatsheet = CHEATSHEET.read_text(encoding="utf-8")
        self.periodic = PERIODIC.read_text(encoding="utf-8")

    def test_the_budget_comes_from_the_monitors_reserved_area(self):
        self.assertIn("HyprlandData.monitors", self.cheatsheet,
                      "the reserve the bar and the dock hold is only in hyprctl's monitor list")
        self.assertIn(".reserved", self.cheatsheet)
        self.assertIn("CheatsheetFit.usableHeight(", self.cheatsheet)
        self.assertIn("CheatsheetFit.pageBudget(", self.cheatsheet)

    def test_no_page_is_budgeted_by_a_literal_allowance(self):
        # `- 220` was the bar, the dock and the chrome on one desktop, and it
        # was the only budget any page had. A literal here is that again.
        self.assertNotRegex(self.cheatsheet, r"screen\?\.height[^\n]*-\s*\d{2,}",
                            "a page's height budget must be derived, not a literal off the screen height")
        self.assertNotIn("- 220", self.cheatsheet)

    def test_every_page_that_can_outgrow_the_screen_takes_the_height_budget(self):
        for page in ("CheatsheetKeybinds", "CheatsheetPeriodicTable"):
            block = re.search(page + r"\s*\{(.*?)\n\s*\}", self.cheatsheet, re.S)
            self.assertIsNotNone(block, f"{page} must be instantiated with a body")
            self.assertIn("maxContentHeight: cheatsheetRoot.pageHeightBudget", block.group(1),
                          f"{page} must take the window's height budget")
            self.assertIn("maxContentWidth: cheatsheetRoot.pageWidthBudget", block.group(1),
                          f"{page} must take the window's width budget")

    def test_the_elements_page_scales_itself_into_the_budget(self):
        self.assertIn("property real maxContentHeight", self.periodic)
        self.assertIn("property real maxContentWidth", self.periodic)
        self.assertRegex(self.periodic, r"CheatsheetFit\.fitScale\(",
                         "the shrink has to be the shared arithmetic, or it drifts from the budget")
        # The scale has to reach what is drawn AND what is reported: a scaled
        # column whose page still reports the natural size sizes the window
        # to the natural size, which is the clipping this exists to remove.
        self.assertIn("scale: root.fit", self.periodic)
        self.assertRegex(self.periodic, r"implicitWidth:\s*mainLayout\.implicitWidth \* root\.fit")
        self.assertRegex(self.periodic, r"implicitHeight:\s*mainLayout\.implicitHeight \* root\.fit")


if __name__ == "__main__":
    unittest.main()
