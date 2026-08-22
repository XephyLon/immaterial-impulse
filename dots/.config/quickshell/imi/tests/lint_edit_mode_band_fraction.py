#!/usr/bin/env python3
"""Fail if Edit Mode's chrome centres itself in a band that is not symmetric.

The band above and below the shrunk desktop is `edgeMargin + toolbarHeight +
margin` - a tight gap on the outside where the toolbar floats against the
screen edge, a generous one on the inside against the desktop. `edit_mode.js`'s
`chromeBandFraction` is that split, and `EditModeChromeContent` places the
toolbar at it and the tab bar at its mirror.

Both halves are invisible when they disagree, which is why this is static:

  - The band reserved asymmetrically but the piece still placed with `/ 2`
    leaves the toolbar 6px off the gap it was given. `tst_edit_mode.qml` covers
    the arithmetic and cannot see the placement, because the placement is a QML
    binding on a rect the arithmetic never returns.
  - A call site that instantiates the content and forgets `bandFraction` gets
    the property's 0.5 default, which is silently the OLD behaviour on a band
    that is no longer symmetric. Nothing errors; the chrome is just wrong by
    the difference between the two margins, and only on a screen where the
    vertical axis binds.

Same shape as `lint_blur_region_pairing.py`: two files, either alone broken,
neither announcing itself at runtime.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEOMETRY = ROOT / "modules/common/functions/edit_mode.js"
CONTENT = ROOT / "modules/imi/editMode/EditModeChromeContent.qml"

# Every file that puts an `EditModeChromeContent { ... }` on screen. Found
# rather than listed: a third surface is exactly the case that would be missed.
INSTANTIATES = re.compile(r"\bEditModeChromeContent\s*\{")
SETS_FRACTION = re.compile(r"^\s*bandFraction:\s*\S", re.M)

# The two placements inside the content, matched on the property they place
# rather than on their whole expression, so a reworded comment does not fail.
TOOLBAR_Y = re.compile(
    r"y:\s*root\.area\.y\s*\+\s*\(root\.card\.y[^\n]*\)\s*\*\s*root\.bandFraction")
TAB_BAR_Y = re.compile(r"\*\s*\(1\s*-\s*root\.bandFraction\)")


def qml_files():
    return sorted(p for p in ROOT.rglob("*.qml") if ".git" not in p.parts)


class EditModeBandFraction(unittest.TestCase):
    def test_the_geometry_declares_the_split(self):
        text = GEOMETRY.read_text()
        self.assertIn("function chromeBandFraction(", text,
                      "edit_mode.js no longer exports the band's split; the "
                      "content's placement reads a function that is gone")
        self.assertRegex(
            text, r"\?\s*edgeMargin\s*\+\s*chromeThickness\s*\+\s*margin",
            "the band is no longer reserved as edgeMargin + chrome + margin, "
            "so the fraction the chrome is placed at is a split of nothing")

    def test_the_content_places_both_pieces_on_the_fraction(self):
        text = CONTENT.read_text()
        self.assertRegex(
            text, TOOLBAR_Y,
            "the toolbar is not placed at `bandFraction` through its band")
        self.assertRegex(
            text, TAB_BAR_Y,
            "the tab bar is not placed at the band's mirrored fraction")
        # The specific regression: centring survives as `/ 2` on a band that is
        # not symmetric, which renders as a toolbar off its gap by half the
        # difference between the two margins.
        for line in text.splitlines():
            if "root.card.y - root.area.y - height" in line:
                self.assertNotIn(
                    "/ 2", line,
                    "the toolbar is still centred in its band with `/ 2`")

    def test_every_call_site_hands_the_fraction_down(self):
        missing = []
        for path in qml_files():
            text = path.read_text()
            if not INSTANTIATES.search(text):
                continue
            if not SETS_FRACTION.search(text):
                missing.append(path.relative_to(ROOT).as_posix())
        self.assertEqual(
            [], missing,
            "these instantiate EditModeChromeContent without setting "
            "`bandFraction`, so they silently take the 0.5 default and centre "
            "the chrome in a band that is not symmetric: " + ", ".join(missing))


if __name__ == "__main__":
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
