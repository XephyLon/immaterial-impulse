#!/usr/bin/env python3
"""The privacy indicator is drawn from the bar's palette, not the error pair.

A vivid colError pill with colOnError glyphs was the one thing on the bar
not in its palette, and read as a fault rather than a status. Under M3 it
is a tonal primary-container pill like the other M3 group pills; under every
other style there is no pill, the glyphs sit on the bar in the accent the
way a live state reads elsewhere on it, and hover is the layer's pill.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "modules/imi/bar/PrivacyIndicator.qml"


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))


class PrivacyIndicatorPaletteTests(unittest.TestCase):
    def setUp(self):
        self.src = strip_comments(SOURCE.read_text(encoding="utf-8"))

    def test_no_error_colours(self):
        for token in ("colError", "colOnError", "colErrorContainer"):
            self.assertNotRegex(self.src, r"\b" + token + r"\b", f"{token} is for faults; the indicator is a status")

    def test_m3_is_a_tonal_primary_container_pill(self):
        self.assertRegex(self.src, r"readonly property bool isMaterial: Config\.options\.bar\.cornerStyle === 3")
        self.assertRegex(self.src, r"pillColor: root\.isMaterial\s*\?\s*\(root\.containsMouse \? Appearance\.colors\.colPrimaryContainerHover : Appearance\.colors\.colPrimaryContainer\)")
        self.assertRegex(self.src, r"onColor: root\.isMaterial \? Appearance\.colors\.colOnPrimaryContainer : Appearance\.colors\.colPrimary")

    def test_other_styles_have_no_pill_and_accent_glyphs(self):
        self.assertRegex(self.src, r':\s*\(root\.containsMouse \? Appearance\.colors\.colLayer1Hover : "transparent"\)')

    def test_hover_is_a_colour_not_a_dim(self):
        self.assertNotIn("0.88", self.src)
        self.assertRegex(self.src, r"Behavior on color \{\s*animation: Appearance\.animation\.\w+\.colorAnimation\.createObject\(this\)")


if __name__ == "__main__":
    unittest.main()
