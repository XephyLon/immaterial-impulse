#!/usr/bin/env python3
"""Source contract: the media widget's spans are one list, in three files.

The host resolves which span a placed widget is (`__gridSize`,
docs/widget-grid.md), `media_layouts.js`'s table turns it into cell counts,
and `media_geometry.js` places every shared element for it. Before the one
tree there was a fourth file per span - a layout - and the drift this module
guards against was a span offered with no layout, which silently drew the
default squeezed into the wrong box. The layouts are gone; the drift is not:
a span offered with no GEOMETRY now falls through `transportRects` to null
and the tree draws a card with no controls at all, only at the one span
nobody was looking at.

`tests/tst_media_layouts.qml` and `tst_media_geometry.qml` drive the lookups
themselves; this is the half that can see the manifest.
"""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "modules/common/plugins/bundled/nandoroid-media"
MANIFEST = PACKAGE / "manifest.json"
LAYOUTS = PACKAGE / "media_layouts.js"
GEOMETRY = PACKAGE / "media_geometry.js"

ENTRY = re.compile(
    r'\{\s*size:\s*"(?P<size>\d+x\d+)"\s*,\s*'
    r'cols:\s*(?P<cols>\d+)\s*,\s*'
    r'rows:\s*(?P<rows>\d+)\s*\}')


def table():
    body = LAYOUTS.read_text(encoding="utf-8")
    start = body.index("var SPANS = [")
    end = body.index("];", start)
    return [match.groupdict() for match in ENTRY.finditer(body[start:end])]


def grid():
    return json.loads(MANIFEST.read_text(encoding="utf-8"))["grid"]


class TheManifestAndTheTableNameTheSameSpans(unittest.TestCase):
    def test_the_table_is_not_empty(self):
        # The regex is the only thing standing between this whole module and a
        # vacuous pass, so say so out loud.
        self.assertEqual(len(table()), 4, "media_layouts.js parsed to nothing")

    def test_every_offered_span_is_in_the_table(self):
        offered = [f"{size['cols']}x{size['rows']}" for size in grid()["sizes"]]
        known = [entry["size"] for entry in table()]
        self.assertEqual(offered, known,
                         "the manifest's sizes and media_layouts.js's table "
                         "must name the same spans, in the same order - the "
                         "order is the resize order the grip walks")

    def test_every_entry_agrees_with_its_own_cell_counts(self):
        for entry in table():
            self.assertEqual(entry["size"], f"{entry['cols']}x{entry['rows']}",
                             f"entry {entry['size']} disagrees with its cells")

    def test_every_offered_span_has_geometry(self):
        """The tree draws what the geometry places; a span without a branch in
        media_geometry.js renders a card with no controls, silently, at that
        one span."""
        geometry = GEOMETRY.read_text(encoding="utf-8")
        for entry in table():
            self.assertIn(f'span === "{entry["size"]}"', geometry,
                          f"media_geometry.js places nothing at {entry['size']}")

    def test_the_fallback_entry_is_the_manifest_default(self):
        """An unrecognised span resolves to the table's first entry, and the
        host resolves an unrecognised stored span to the manifest default. Those
        two answers have to be the same span, or the one case where both fire -
        a stored span dropped from the manifest - draws one size's geometry at
        another size's pixels.
        """
        default = grid()
        self.assertEqual(table()[0]["size"],
                         f"{default['cols']}x{default['rows']}")


if __name__ == "__main__":
    unittest.main()
