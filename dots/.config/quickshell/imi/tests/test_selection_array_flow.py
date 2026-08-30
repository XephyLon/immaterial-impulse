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


if __name__ == "__main__":
    unittest.main()
