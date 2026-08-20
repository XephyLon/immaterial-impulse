#!/usr/bin/env python3
"""What sizes an on-screen keyboard key, held in the source.

`tst_osk_layouts.qml` reads the real layout data and the real shape tables, so
it can prove that every row spans the same 23 keyboard units. What it cannot
see is the conversion from a unit to a pixel, which lives in OskKey.qml - and
all three of the ways that conversion has already gone wrong are invisible from
the data:

  - a second copy of the shape tables or of the cap's own metrics. Both used to
    be declared inside OskKey.qml, which is why the QML test would have been
    testing a transcription; a table growing back there is a second answer to
    how wide a key is, and the layouts - and the lattice the keys are placed
    on - are written against the other one.
  - a key gap that is not the row's gap. A key spanning several units swallows
    the gaps it covers, so OskKey subtracts exactly what OskContent's RowLayout
    puts between two keys. Two different tokens leave every wide key short by a
    few pixels per unit and every column after it displaced.
  - a key that fills the row. `Layout.fillWidth` is how the rows used to come
    out the same width, and it works only while the fill key is the last thing
    in the row. Behind a nav cluster and a numpad it hands every key after it a
    position that depends on that row's own leftover.

Run: python3 tests/test_osk_key_contract.py
"""
import re
import unittest
from pathlib import Path

from test_background_fullscreen_suppression import _qml_source

ROOT = Path(__file__).resolve().parents[1]
OSK_DIR = ROOT / "modules/imi/onScreenKeyboard"
OSK_KEY = OSK_DIR / "OskKey.qml"
OSK_CONTENT = OSK_DIR / "OskContent.qml"
KEY_SHAPES = OSK_DIR / "key_shapes.js"
APPEARANCE = ROOT / "modules/common/Appearance.qml"


def _shape_metric(name):
    """The pixel value behind a key_shapes.js cap metric."""
    match = re.search(rf"(?m)^const {name} = (\d+);", KEY_SHAPES.read_text())
    assert match is not None, f"key_shapes.js declares no {name}"
    return int(match.group(1))


def _spacing_token(name):
    """The pixel value behind an Appearance.spacing.* token."""
    match = re.search(rf"property int {name}:\s*(\d+)", APPEARANCE.read_text())
    assert match is not None, f"Appearance declares no {name}"
    return int(match.group(1))


class OskKeyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key = _qml_source(OSK_KEY).code
        cls.content = _qml_source(OSK_CONTENT).code
        cls.shapes = KEY_SHAPES.read_text()

    def test_the_shape_tables_have_one_home(self):
        self.assertIn('import "key_shapes.js" as KeyShapes', self.key,
                      "OskKey no longer imports the shape tables")
        for table in ("widthUnits", "heightUnits"):
            self.assertRegex(
                self.shapes, rf"(?m)^const {table} = {{",
                f"key_shapes.js does not declare {table}")
            self.assertRegex(
                self.key, rf"KeyShapes\.{table}\[",
                f"OskKey does not resolve a shape through KeyShapes.{table}")
        # A table declared in the QML is a second answer to how wide a key is,
        # and the layouts are written against the one in key_shapes.js.
        self.assertNotRegex(
            self.key, r"property\s+var\s+\w*(?:Multiplier|Units)\s*:\s*\(?\{",
            "OskKey declares a shape table of its own")
        # The cap's own box lives there too, because osk_lattice.js derives the
        # grid column from it. A literal here is a second answer to the pitch,
        # and the lattice would keep placing keys on the old one.
        for prop, metric in (("baseWidth", "baseKeyWidth"),
                             ("baseHeight", "baseKeyHeight")):
            self.assertRegex(
                self.key, rf"property real {prop}:\s*KeyShapes\.{metric}\b",
                f"OskKey does not take {prop} from KeyShapes.{metric}")

    def test_a_key_subtracts_the_gap_its_row_puts_between_keys(self):
        gap = re.search(r"property real keyGap:\s*(Appearance\.spacing\.\w+)", self.key)
        self.assertIsNotNone(gap, "OskKey declares no keyGap")
        spacing = re.findall(r"spacing:\s*(Appearance\.spacing\.\w+)", self.content)
        self.assertTrue(spacing, "OskContent declares no row spacing")
        for token in spacing:
            self.assertEqual(
                token, gap.group(1),
                "OskContent lays its keys out on a different gap from the one "
                "OskKey subtracts, so every key wider than one unit is drawn "
                "short by the difference and every column after it moves.")

    def test_a_key_computes_its_width_from_units_and_that_gap(self):
        self.assertRegex(
            self.key,
            r"implicitWidth:\s*root\.baseWidth \* root\.widthUnits"
            r" \+ root\.keyGap \* \(root\.widthUnits - 1\)",
            "a key's width no longer covers the gaps its span swallows")
        # The pitch has to stay a multiple of four or a quarter-unit span lands
        # on a half pixel, which QQuickLayout rounds up - seven pixels of drift
        # across the function row's fourteen spacers.
        gap = re.search(r"property real keyGap:\s*Appearance\.spacing\.(\w+)", self.key)
        self.assertIsNotNone(gap, "OskKey declares no keyGap")
        pitch = _shape_metric("baseKeyWidth") + _spacing_token(gap.group(1))
        self.assertEqual(pitch % 4, 0,
                         f"the key pitch is {pitch}, which cannot draw a "
                         f"quarter unit in whole pixels")

    def test_no_key_fills_its_row(self):
        self.assertNotIn(
            "Layout.fillWidth", self.key,
            "a key that fills the row puts every key after it wherever that "
            "row's leftover lands, which is the numpad drifting per row")


if __name__ == "__main__":
    unittest.main()
