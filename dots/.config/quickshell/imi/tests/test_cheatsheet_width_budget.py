#!/usr/bin/env python3
"""The cheatsheet's pages have to answer to the screen's width as well as its
height, and the window has to answer to the page on screen.

`columnCount` picks columns from a *row* budget - how many keybind rows fit
vertically before the card grows past the screen. Columns trade height for
width, so a full keybind set can exceed BOTH budgets at once on a laptop:
four columns were ~40px too tall for a 1080p screen and five were ~280px too
wide (measured live), so no column count fits and lowering a cap just picks
which axis overflows. The keybinds page therefore fits the way the Elements
page always has - keep the columns, shrink the whole thing uniformly through
the shared fitScale, full size again on any screen with room.

The window half: it is fixed-size (equal min/max hints float and centre it),
and it used to be sized to the *tallest* page - so the typing test opened as
tall as the keybind table and the whole window ran past the screen. It sizes
to the current page now.
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

    def test_the_keybinds_page_scales_itself_into_both_budgets(self):
        self.assertIn("property real maxContentWidth", self.keybinds)
        self.assertIn("property real maxContentHeight", self.keybinds)
        self.assertRegex(self.keybinds, r"CheatsheetFit\.fitScale\(",
                         "the shrink has to be the shared arithmetic, or it drifts from the budget")
        # The scale has to reach what is drawn AND what is reported: a scaled
        # row whose page still reports the natural size sizes the window to
        # the natural size, which is the overflow this exists to remove.
        self.assertIn("scale: root.fit", self.keybinds)
        self.assertRegex(self.keybinds, r"implicitWidth:\s*root\.contentWidth \* root\.fit")
        self.assertRegex(self.keybinds, r"implicitHeight:\s*root\.contentHeight \* root\.fit")

    def test_the_window_is_sized_to_the_current_page_not_the_tallest(self):
        # Math.max over every page is how the typing test opened at the keybind
        # table's height - the fixed-size window must follow the tab.
        swipe = re.search(r"SwipeView \{(.*?)\n                    \}", self.cheatsheet, re.S)
        self.assertIsNotNone(swipe, "the SwipeView must exist")
        body = swipe.group(1)
        self.assertNotIn("Math.max.apply", body,
                         "the window must not be sized to the tallest page")
        for axis in ("implicitWidth", "implicitHeight"):
            self.assertRegex(
                body,
                axis + r":\s*\(swipeView\.contentChildren\[swipeView\.currentIndex\]\?\." + axis + r"\)",
                f"the SwipeView's {axis} must read the current page's")


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
