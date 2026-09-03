#!/usr/bin/env python3
"""A segmented row's chips lay out on the width they need, labelled or not.

A Flow with no width of its own takes its implicitWidth, and a Flow computes
THAT from the width it currently has - so the two define each other, and a row
built across frames (which is how a settings page is built) latches at a
narrow intermediate width with every chip on its own line. 4ef84e521 broke
the circle by handing the layout the chips' summed natural width as the
Flow's preferred width - but only when the row had a label. The Quick page's
Bar & Screen cards use the row WITHOUT one (`Layout.fillWidth: false`,
right-aligned under a heading of their own), and the same four chips latched
one per line there: measured on the real page through QuickPageProbe.qml,
four flows at 4/4/3/2 lines before, all six on one line after.

So the preferred width is handed over on both paths, and this holds it there.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROW = ROOT / "modules/common/widgets/ConfigSelectionArray.qml"


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


class SelectionArrayFlowTests(unittest.TestCase):
    def setUp(self):
        self.source = strip_comments(ROW.read_text())

    def test_the_flow_sums_its_chips_natural_width(self):
        self.assertIn("readonly property real naturalWidth:", self.source,
                      "the Flow no longer computes a width that owes nothing to itself")

    def test_the_natural_width_is_preferred_on_both_paths(self):
        match = re.search(r"Layout\.preferredWidth:\s*(.+)", self.source)
        self.assertIsNotNone(match, "the Flow hands the layout no preferred width - "
                                    "its width and its implicitWidth define each other again")
        expression = match.group(1).strip()
        self.assertEqual(expression, "buttonsFlow.naturalWidth",
                         f"the preferred width is conditional ({expression}); the path it "
                         f"leaves out is the one that latches one chip per line")


    # The other half, found when a fifth bar style joined: an aligned child is
    # handed its preferred size and never resized, so a row narrower than its
    # chips OVERFLOWED rather than wrapping - the Quick page's Bar style card
    # drew its last chip past the card's edge (461px Flow, 442px card). On the
    # unlabelled path the Flow fills its cell up to the natural width as a
    # maximum; measured through QuickPageProbe.qml: 316px, two lines, 0 over.
    def test_an_unlabelled_flow_fills_up_to_its_natural_width_so_it_can_wrap(self):
        text = strip_comments(ROW.read_text(encoding="utf-8"))
        match = re.search(r"Layout\.maximumWidth:\s*(.+)", text)
        self.assertIsNotNone(match, "the Flow hands the layout no maximum, so it can never be given less")
        self.assertEqual(match.group(1).strip(), "buttonsFlow.naturalWidth")
        # Both paths fill now; the label holds its own minimum so it is the
        # chips that yield when a labelled row is short of room.
        flow = text[text.index("Flow {"):]
        self.assertRegex(flow, r"Layout\.fillWidth:\s*true")
        self.assertRegex(text, r"id: labelWidget\s*\n\s*Layout\.fillWidth: true\s*\n\s*Layout\.minimumWidth: labelWidget\.implicitWidth")

    def test_the_quick_pages_card_rows_take_their_cards_width(self):
        quick = strip_comments((ROOT / "modules/imi/settings/pages/QuickConfig.qml").read_text(encoding="utf-8"))
        arrays = re.findall(r"ConfigSelectionArray \{(.*?)\n\s{24}\}", quick, re.S)
        card_rows = [a for a in arrays if "currentValue: Config.options.bar." in a]
        self.assertGreaterEqual(len(card_rows), 2)
        for body in card_rows:
            self.assertNotIn("Layout.fillWidth: false", body,
                             "a row that refuses width cannot wrap, and overflows its card instead")

    def test_the_bar_and_screen_cards_stack_in_one_column(self):
        # The page is 720 wide. Two columns hand each card 316px of content and
        # only one of the four chip rows fits that; the rest overflowed, or,
        # once they could wrap, left an orphan chip on a second line beside a
        # neighbour of a different height. One card per row holds every chip
        # row on one line: measured 461px, the widest, in a 720px row.
        quick = strip_comments((ROOT / "modules/imi/settings/pages/QuickConfig.qml").read_text(encoding="utf-8"))
        section = quick[quick.index('Translation.tr("Bar & Screen")'):quick.index('Translation.tr("Screen round corner")')]
        self.assertRegex(section, r"GridLayout \{[^}]*?columns:\s*1\b",
                         "the Bar & Screen cards must stack, or the chip rows cannot fit")


    # A labelled row whose chips cannot share the line stacks them beneath the
    # label instead of wrapping them beside it (the clock's "Minute hand" row
    # put "Bold" alone on a second line next to a centred label).
    def test_a_labelled_row_that_cannot_fit_stacks_its_chips_under_the_label(self):
        text = strip_comments(SOURCE.read_text(encoding="utf-8")) if "SOURCE" in globals() else strip_comments(ROW.read_text(encoding="utf-8"))
        self.assertRegex(text, r"readonly property bool stacked: root\.text !== \"\"\s*&& labelGroup\.implicitWidth \+ rowGrid\.columnSpacing \+ buttonsFlow\.naturalWidth > rowGrid\.width")
        self.assertRegex(text, r"Layout\.row: rowGrid\.stacked \? 1 : 0")
        self.assertRegex(text, r"Layout\.columnSpan: rowGrid\.stacked \? 3 : 1")


if __name__ == "__main__":
    unittest.main()
