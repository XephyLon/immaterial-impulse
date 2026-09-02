#!/usr/bin/env python3
"""A quick toggle's edit-mode badges sit inside the tile, both on its right edge.

They hung 8px outside opposite corners - remove at the top-left, resize at
the bottom-right - so in an 8px gutter one tile's remove badge landed beside
its neighbour's resize handle and a user could not tell which tile either
belonged to, while the bottom row's handles fell outside the grid and were
clipped. Inside the tile, on one edge, a badge can only be its own tile's
and nothing clips it.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
TILE = ROOT / "modules/imi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml"


def block(text, ident):
    match = re.search(r"Rectangle \{\s*id: " + ident + r"(.*?)\n    \}", text, re.S)
    return match.group(1) if match else None


class EditBadgeTests(unittest.TestCase):
    def setUp(self):
        self.src = re.sub(r"//[^\n]*", "", TILE.read_text(encoding="utf-8"))

    def test_both_badges_sit_on_the_right_edge_inside_the_tile(self):
        for ident, vertical in (("deleteBtn", "top"), ("resizeBtn", "bottom")):
            body = block(self.src, ident)
            self.assertIsNotNone(body, ident)
            self.assertRegex(body, r"anchors\.right: parent\.right")
            self.assertRegex(body, r"anchors\." + vertical + r": parent\." + vertical)
            self.assertNotRegex(body, r"Margin: -", f"{ident}: a negative margin hangs the badge outside the tile")
            self.assertRegex(body, r"anchors\.rightMargin: Appearance\.spacing\.")


if __name__ == "__main__":
    unittest.main()
