#!/usr/bin/env python3
"""Source contract: the Size row and the drag grip are one value.

A widget whose manifest offers more than one span already resizes by dragging
its corner. The grip is quick and it is also invisible until hovered, so the
same span is offered as a row in Settings > Widgets - discoverable, and
reachable from the keyboard.

What makes them one thing rather than two is that both read and write the
host's `__gridSize`, in `gridSizes.js`'s `"<cols>x<rows>"` form. A row writing
any other key, or the same key in another format, would be a second size the
widget does not have.

The gate is the other half. Not every widget is resizable: a widget qualifies
only when it has a design per size, so the row is *omitted* where the manifest
names one span, not shown disabled. A control that can never be enabled is
noise, and one that offers a span the widget has no layout for is worse than
no row at all.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
OPTIONS = ROOT / "modules/common/plugins/PluginOptions.qml"
HOST = ROOT / "modules/common/plugins/PluginWidget.qml"
GRID_SIZES = ROOT / "modules/common/plugins/gridSizes.js"


def squashed(path: Path) -> str:
    return re.sub(r"\s+", " ", path.read_text(encoding="utf-8"))


class TheRowAndTheGripShareOneValue(unittest.TestCase):
    def setUp(self):
        self.options = squashed(OPTIONS)
        self.host = squashed(HOST)

    def test_the_row_writes_the_key_the_grip_writes(self):
        self.assertIn('key: "__gridSize"', self.options)
        self.assertIn('PluginState.setOption(manifest.id, "__gridSize"', self.host,
                      "the grip's writer moved; the row now writes a key "
                      "nothing reads")

    def test_the_choices_are_formatted_by_the_module_that_parses_them(self):
        """A row spelling the span itself is a second format to keep in step,
        and `resolveSize` would silently reject anything it cannot parse -
        leaving the widget at its default with the row showing a size it is
        not.
        """
        self.assertIn("value: GridSizes.formatSize(size)", self.options)
        self.assertIn("function formatSize(size)",
                      GRID_SIZES.read_text(encoding="utf-8"))

    def test_the_spans_offered_are_the_ones_the_host_resolves_against(self):
        self.assertIn("GridSizes.offeredSizes(manifest.grid)", self.options)
        self.assertIn("GridSizes.offeredSizes(rootWidget.gridSpec)", self.host)

    def test_the_default_is_the_manifest_s_own_span(self):
        self.assertIn("default: GridSizes.formatSize(GridSizes.defaultSize(manifest.grid))",
                      self.options)


class TheRowIsOmittedWhereItCannotApply(unittest.TestCase):
    def setUp(self):
        self.options = squashed(OPTIONS)

    def test_it_needs_more_than_one_offered_span(self):
        self.assertRegex(
            self.options,
            r"readonly property var sizeRows: root\.offeredSizes\.length > 1 \?",
            "a widget with one span must get no size row at all")

    def test_the_empty_case_is_an_empty_list_not_a_disabled_row(self):
        rows = self.options[self.options.index("readonly property var sizeRows"):]
        rows = rows[:rows.index("Repeater {")]
        self.assertIn("] : []", rows)
        self.assertNotIn("enabled:", rows,
                         "the row is omitted where it cannot apply, never "
                         "greyed out - greying is for rows that are only "
                         "temporarily inert")

    def test_it_is_a_choice_row_so_the_generic_delegate_draws_it(self):
        """`choice` is already in PluginValidator's type whitelist and
        PluginOptions' delegate switch. An unlisted type renders nothing.
        """
        rows = self.options[self.options.index("readonly property var sizeRows"):]
        rows = rows[:rows.index("Repeater {")]
        self.assertIn('type: "choice"', rows)


if __name__ == "__main__":
    unittest.main(verbosity=2)
