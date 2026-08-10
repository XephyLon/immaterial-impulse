#!/usr/bin/env python3
"""The auto-hidden bar's reveal strip is the window's whole input region, and it
has to stay inside the window.

While the bar is hidden its content sits at `y = -barHeight`. Anchoring the mask
item to that content with negative margins - the obvious way to write "the bar
plus a couple of pixels either side" - published a rect starting roughly a whole
bar height above the surface and left the compositor to clamp it. What survives
clamping is only `hoverRegionWidth` tall (2px by default), so an off-by-one
costs half the strip, and the row that goes missing is `y = 0`: the screen edge,
which is where a pointer thrown at the top of the screen actually lands.

Clamping is therefore not a tidy-up. It is the difference between the strip
being reachable and not.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
BAR = ROOT / "modules/imi/bar/Bar.qml"


class BarHoverRegionTests(unittest.TestCase):
    def setUp(self):
        self.bar = BAR.read_text(encoding="utf-8")
        block = re.search(r"Item \{\s*\n\s*id: hoverMaskRegion(.*?)\n                    \}",
                          self.bar, re.S)
        self.assertIsNotNone(block, "hoverMaskRegion must exist - it is the bar's input region")
        self.block = block.group(1)

    def test_the_strip_is_not_anchored_to_the_offscreen_content(self):
        # `fill: barContent` with negative margins is the shape that put the
        # rect outside the surface.
        self.assertNotIn("fill: barContent", self.block)
        self.assertNotRegex(self.block, r"topMargin:\s*-",
                            "a negative top margin puts the region above the surface")
        self.assertNotRegex(self.block, r"bottomMargin:\s*-")

    def test_the_strip_is_clamped_into_the_window(self):
        self.assertIn("Math.max(0,", self.block,
                      "the top edge has to clamp at 0 or the rect starts outside the surface")
        self.assertIn("Math.min(parent.height,", self.block,
                      "the bottom edge has to clamp at the surface height, for a bottom bar")
        self.assertRegex(self.block, r"height:\s*Math\.max\(0,",
                         "a negative height is not a small region, it is an invalid one")

    def test_the_strip_still_covers_the_reveal_width_either_side(self):
        # Clamping must not quietly drop the overshoot that makes the strip
        # reachable before the bar has finished sliding in.
        self.assertIn("hoverRegionWidth", self.block)
        self.assertIn("barContent.y - reveal", self.block)
        self.assertIn("barContent.y + barContent.height + reveal", self.block)


if __name__ == "__main__":
    unittest.main()
