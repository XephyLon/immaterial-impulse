#!/usr/bin/env python3
"""Source contract: bundled desktop widgets must sit on the component grid.

The grid cell is 132 x 108 with a 12px gap - it is NOT square and the row is
NOT 120 tall. Two independent widget ports (world clock, calendar) copied the
built-in's pre-grid pixel heights verbatim on the assumption that a "2x2" was
276x252 and a one-row widget was 120 tall. Both were off the lattice, so they
never lined up with a real grid widget placed beside them.

Nothing catches that at runtime: an off-lattice widget renders perfectly, it
just refuses to tile. These are greppable pins so it cannot come back.

Two rules:
  1. A widget-level size is expressed with Appearance.sizes.widgetGridSpanX/Y,
     never a pixel literal. A literal is both wrong on the lattice and wrong on
     any scaled setup, because the helpers multiply by effectiveScale.
  2. A manifest's defaultWidth/defaultHeight floor is itself a real span.
"""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUNDLED = ROOT / "modules/common/plugins/bundled"
APPEARANCE = ROOT / "modules/common/Appearance.qml"

# Widgets that documentedly cannot express themselves through the grid, with
# the reason from docs/widget-grid.md. Everything else must be on it.
OFF_GRID_BY_DESIGN = {
    "clock": "predates the grid, left content-sized",
    "custom-image": "user-resizable and square; no span is square",
    "discordVoice": "panel-style widget sized by its participant list",
    "docker": "content-sized list, no fixed span",
    "visualizer": "full-bleed; spanX caps at 12 cols",
}

# Thin wrappers whose Widget.qml only forwards the implicit size of a
# designsystem widget. Those designsystem widgets are where the grid comes from
# in the first place (docs/widget-grid.md: "the nandoroid-* widgets already
# conform... they define this grid"), so the span lives one file down.
DELEGATES_TO_THE_DESIGN_SYSTEM = {
    "nandoroid-currency",
    "nandoroid-media",
    "nandoroid-system-monitor",
    "nandoroid-weather",
}

# Root-level size properties. Indentation pins them to the widget's own root
# object, so inner components (a 28px day cell, a 40px avatar) are not caught.
ROOT_SIZE_PROP = re.compile(
    r"^ {0,4}(?:readonly\s+)?(?:property\s+(?:real|int)\s+)?"
    r"(implicitWidth|implicitHeight|widgetWidth|widgetHeight|\w*(?:Width|Height|Size))"
    r"\s*:\s*(.+)$"
)
INT_LITERAL = re.compile(r"(?<![\w.])(\d{3,})(?![\w.])")

# Only sizes at widget scale matter; a two-digit literal is never a span.
WIDGET_SCALE = 100


def spans():
    src = APPEARANCE.read_text(encoding="utf-8")

    def token(name):
        return int(re.search(rf"property real {name}:\s*(\d+)", src).group(1))

    cell_w, cell_h, gap = (token("widgetGridCellWidth"),
                           token("widgetGridCellHeight"),
                           token("widgetGridGap"))
    return (
        {n: n * cell_w + (n - 1) * gap for n in range(1, 13)},
        {n: n * cell_h + (n - 1) * gap for n in range(1, 13)},
    )


SPAN_X, SPAN_Y = spans()


class TheGridIsNotSquare(unittest.TestCase):
    """Pins the numbers the two bad ports guessed wrong."""

    def test_cell_height_is_108_not_120(self):
        self.assertEqual(SPAN_Y[1], 108,
                         "a one-row widget is 108 tall, not 120")

    def test_a_two_by_two_tile_is_276_by_228(self):
        self.assertEqual((SPAN_X[2], SPAN_Y[2]), (276, 228),
                         "a 2x2 tile is 276x228, not 276x252")

    def test_420_wide_is_three_columns_not_four(self):
        self.assertEqual(SPAN_X[3], 420)
        self.assertNotEqual(SPAN_X[4], 420,
                            "420 is spanX(3); a 4-column widget is 564 wide")


class RootSizesGoThroughTheGridHelpers(unittest.TestCase):
    """No bundled widget may hardcode a widget-scale pixel size."""

    def test_no_widget_scale_literal_in_a_root_size_property(self):
        offenders = []
        for widget in sorted(BUNDLED.glob("*/Widget.qml")):
            if widget.parent.name in OFF_GRID_BY_DESIGN:
                continue
            for lineno, line in enumerate(
                    widget.read_text(encoding="utf-8").splitlines(), 1):
                match = ROOT_SIZE_PROP.match(line)
                if not match:
                    continue
                expression = match.group(2).split("//", 1)[0]
                for literal in INT_LITERAL.findall(expression):
                    if int(literal) >= WIDGET_SCALE:
                        offenders.append(
                            f"{widget.parent.name}/Widget.qml:{lineno}  "
                            f"{match.group(1)}: {literal}")
        self.assertEqual(offenders, [],
                         "widget sizes must use Appearance.sizes."
                         "widgetGridSpanX/Y, not pixel literals:\n  "
                         + "\n  ".join(offenders))

    def test_every_on_grid_widget_actually_calls_a_span_helper(self):
        """The rule above is satisfied by binding to nothing at all, so also
        require that a widget which is meant to be on the grid says so.
        """
        for widget in sorted(BUNDLED.glob("*/Widget.qml")):
            name = widget.parent.name
            if name in OFF_GRID_BY_DESIGN or name in DELEGATES_TO_THE_DESIGN_SYSTEM:
                continue
            manifest = json.loads(
                (widget.parent / "manifest.json").read_text(encoding="utf-8"))
            src = widget.read_text(encoding="utf-8")
            if "grid" in manifest:
                # The host assigns the span; the widget only needs a fallback.
                continue
            self.assertTrue(
                re.search(r"Appearance\.sizes\.widgetGridSpan[XY]\(", src),
                f"{name} declares no manifest grid, so its own size must come "
                "from Appearance.sizes.widgetGridSpanX/Y")


class PortedWidgetsDeclareTheSpansTheyActuallyOccupy(unittest.TestCase):
    """The two widgets this test was written for, pinned mode by mode."""

    # `widgetWidth`/`widgetHeight` used to name the spans on their own line.
    # They are the ANIMATING box now - both widgets morph in one tree, so the
    # box travels towards a settled span rather than snapping to it - and the
    # span helpers moved one step back, into the `spanWidthOf`/`spanHeightOf`
    # every element's geometry is evaluated at. Both halves are still pinned:
    # the file reaches the lattice through the helpers, and the animating box
    # follows a span rather than a literal.
    def assertBoxFollowsTheSpan(self, src, name):
        width = re.search(r"property real widgetWidth:\s*(.+)", src).group(1)
        height = re.search(r"property real widgetHeight:\s*(.+)", src).group(1)
        self.assertEqual(width.strip(), "root.spanW",
                         f"{name}'s animating box must follow the settled span")
        self.assertEqual(height.strip(), "root.spanH", name)

    def test_world_clock_is_2x2_or_3x1(self):
        src = (BUNDLED / "world-clock/Widget.qml").read_text(encoding="utf-8")
        self.assertIn("widgetGridSpanX(2)", src)
        self.assertIn("widgetGridSpanX(3)", src,
                      "the wide mode is 420px, which is three columns")
        self.assertIn("widgetGridSpanY(2)", src)
        self.assertIn("widgetGridSpanY(1)", src,
                      "the wide mode is one row, so 108 tall - not 120")
        self.assertBoxFollowsTheSpan(src, "world-clock")

    def test_calendar_is_1x1_2x1_or_2x2(self):
        src = (BUNDLED / "calendar/Widget.qml").read_text(encoding="utf-8")
        for call in ("widgetGridSpanX(1)", "widgetGridSpanX(2)",
                     "widgetGridSpanY(1)", "widgetGridSpanY(2)"):
            self.assertIn(call, src, f"calendar must size through {call}")
        self.assertBoxFollowsTheSpan(src, "calendar")


class ManifestFloorsAreRealSpans(unittest.TestCase):
    """defaultWidth/defaultHeight are the host's floor (Math.max against the
    content size). A floor that is not itself a span drags the widget off the
    lattice even when the QML is right.
    """

    def test_floors_land_on_the_lattice(self):
        for manifest_path in sorted(BUNDLED.glob("*/manifest.json")):
            if manifest_path.parent.name in OFF_GRID_BY_DESIGN:
                continue
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            name = manifest_path.parent.name
            if "defaultWidth" in manifest:
                self.assertIn(manifest["defaultWidth"], SPAN_X.values(),
                              f"{name} defaultWidth is not a spanX value")
            if "defaultHeight" in manifest:
                self.assertIn(manifest["defaultHeight"], SPAN_Y.values(),
                              f"{name} defaultHeight is not a spanY value")

    def test_floors_are_the_smallest_span_the_widget_can_take(self):
        """A floor larger than the widget's smallest mode makes that mode
        unreachable, because the host takes the max of floor and content.
        """
        for name, width, height in (("world-clock", SPAN_X[2], SPAN_Y[1]),
                                    ("calendar", SPAN_X[1], SPAN_Y[1])):
            manifest = json.loads(
                (BUNDLED / name / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["defaultWidth"], width, name)
            self.assertEqual(manifest["defaultHeight"], height, name)


class RenamedModesStillReadOldState(unittest.TestCase):
    """world-clock's wide mode was named "4x1" while being three columns, and
    calendar's was "1x2" while being two columns by one row. Renaming the
    persisted value strands whatever is already on disk, so both widgets must
    normalise on read rather than leaving a user with an empty card.
    """

    def test_world_clock_normalises_the_persisted_mode(self):
        src = (BUNDLED / "world-clock/Widget.qml").read_text(encoding="utf-8")
        self.assertTrue(
            re.search(r"property string sizeMode:\s*root\.normalizeSizeMode\(",
                      src),
            "world-clock must normalise the persisted mode on read")
        self.assertIn('"3x1"', src, "the wide mode is three columns")

    def test_world_clock_never_compares_against_the_dead_name(self):
        """`visible: sizeMode === "4x1"` is what would leave a legacy install
        rendering neither branch - an empty card with no error.
        """
        src = (BUNDLED / "world-clock/Widget.qml").read_text(encoding="utf-8")
        self.assertIsNone(re.search(r'sizeMode\s*===\s*"4x1"', src),
                          'world-clock still branches on the dead name "4x1"')

    def test_calendar_normalises_the_persisted_mode(self):
        src = (BUNDLED / "calendar/Widget.qml").read_text(encoding="utf-8")
        self.assertTrue(
            re.search(r"property string sizeMode:\s*root\.normalizeSizeMode\(",
                      src),
            "calendar must normalise the persisted mode on read")
        self.assertIn('"2x1"', src, "the wide-short mode is two columns by one")

    def test_calendar_maps_the_legacy_name_onto_the_same_shape(self):
        """Without the mapping, "1x2" falls through to the switch default and
        silently promotes the user's week strip to the full month.
        """
        src = (BUNDLED / "calendar/Widget.qml").read_text(encoding="utf-8")
        self.assertIn("function normalizeSizeMode", src,
                      "calendar must normalise the persisted mode on read")
        body = src[src.index("function normalizeSizeMode"):]
        body = body[:body.index("\n    }")]
        self.assertIn('"1x2"', body,
                      "normalizeSizeMode must recognise the legacy name")
        self.assertIsNone(re.search(r'sizeMode\s*===\s*"1x2"', src),
                          'calendar still branches on the dead name "1x2"')


if __name__ == "__main__":
    unittest.main(verbosity=2)
