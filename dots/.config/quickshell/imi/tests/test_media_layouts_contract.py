#!/usr/bin/env python3
"""Source contract: the media widget's spans and its layouts are one list.

The host resolves which span a placed widget is (`__gridSize`, docs/widget-grid.md)
and the widget picks the file that draws it, so the manifest's `grid.sizes` and
`media_layouts.js`'s table are two lists that have to name the same set. They
are edited in different files, which is exactly the drift AGENT.md's
validator/renderer note describes: a span offered with no layout of its own does
not fail, it silently draws the default layout squeezed into a box it was never
designed for - and the grip offers that size for the rest of the widget's life.

`tests/tst_media_layouts.qml` drives the lookup itself; this is the half that
can see the manifest.
"""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "modules/common/plugins/bundled/nandoroid-media"
MANIFEST = PACKAGE / "manifest.json"
LAYOUTS = PACKAGE / "media_layouts.js"

ENTRY = re.compile(
    r'\{\s*size:\s*"(?P<size>\d+x\d+)"\s*,\s*'
    r'cols:\s*(?P<cols>\d+)\s*,\s*'
    r'rows:\s*(?P<rows>\d+)\s*,\s*'
    r'layout:\s*"(?P<layout>[^"]+)"\s*\}')


def table():
    body = LAYOUTS.read_text(encoding="utf-8")
    start = body.index("var SIZES = [")
    end = body.index("];", start)
    return [match.groupdict() for match in ENTRY.finditer(body[start:end])]


def grid():
    return json.loads(MANIFEST.read_text(encoding="utf-8"))["grid"]


class TheManifestAndTheTableNameTheSameSpans(unittest.TestCase):
    def test_the_table_is_not_empty(self):
        # The regex is the only thing standing between this whole module and a
        # vacuous pass, so say so out loud.
        self.assertEqual(len(table()), 3, "media_layouts.js parsed to nothing")

    def test_every_offered_span_has_a_layout_of_its_own(self):
        offered = [f"{size['cols']}x{size['rows']}" for size in grid()["sizes"]]
        drawn = [entry["size"] for entry in table()]
        self.assertEqual(offered, drawn,
                         "the manifest's sizes and media_layouts.js's table "
                         "must name the same spans, in the same order - the "
                         "order is the resize order the grip walks")

    def test_every_entry_agrees_with_its_own_cell_counts(self):
        for entry in table():
            self.assertEqual(entry["size"], f"{entry['cols']}x{entry['rows']}",
                             f"entry {entry['size']} disagrees with its cells")

    def test_every_layout_file_exists(self):
        for entry in table():
            self.assertTrue((PACKAGE / entry["layout"]).is_file(),
                            f"{entry['layout']} is named but not shipped")

    def test_the_fallback_entry_is_the_manifest_default(self):
        """An unrecognised span resolves to the table's first entry, and the
        host resolves an unrecognised stored span to the manifest default. Those
        two answers have to be the same span, or the one case where both fire -
        a stored span dropped from the manifest - draws one size's layout at
        another size's pixels.
        """
        default = grid()
        self.assertEqual(table()[0]["size"],
                         f"{default['cols']}x{default['rows']}")


if __name__ == "__main__":
    unittest.main()
