#!/usr/bin/env python3
"""The calendar widget's card, measured in pixels rather than in source text.

`test_expressive_design_system.py` can see that the widget names WidgetCard
and forwards `hostDragging`. It cannot see either of the two ways that
composition fails silently: the widget is content-sized, so a card that did
not resolve leaves a zero-size widget rather than an error, and a `dragging`
that never reaches the card leaves a shadow that simply never lifts.

So this renders the real widget under headless weston - the three modes, and
the tall one a second time with the host reporting a drag - and reads the
strip just below each card.
"""

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROBE = ROOT / "tests/run_calendar_probe.sh"

# The spans the three modes are built from (docs/widget-grid.md): one cell is
# 132x108 and two are 276 wide, 228 tall, with the 12px gap between them.
EXPECTED_BOXES = [(132, 108), (276, 108), (276, 228), (276, 228)]


def darkness(shot, geometry):
    """Mean darkness of a band, 0 = white.

    ImageMagick does the averaging: piping raw grey out of it and summing by
    hand produced values that did not match the visible image at all.
    """
    mean = subprocess.run(
        ["magick", str(shot), "-crop", geometry, "+repage",
         "-colorspace", "Gray", "-format", "%[fx:mean]", "info:"],
        capture_output=True, text=True, timeout=60).stdout.strip()
    return (1.0 - float(mean)) * 255.0


def darkness_below(shot, x, y, width, height):
    """The band just under a card, sampled clear of its rounded corners."""
    return darkness(shot, f"{width - 40}x14+{x + 20}+{y + height + 4}")


def _runtime_available():
    # Same gate the other runtime probes use, plus the analyser: CI has no
    # compositor, and a test that hard-fails there is reporting the runner's
    # shape as a defect in the card.
    return all(shutil.which(tool) is not None
               for tool in ("qs", "weston", "magick"))


@unittest.skipUnless(_runtime_available(), "needs qs, weston and magick on PATH")
class CalendarCardTest(unittest.TestCase):
    def test_the_calendar_composes_a_card_that_paints_and_lifts(self):
        with tempfile.TemporaryDirectory() as tmp:
            shot = Path(tmp) / "calendar.png"
            env = dict(os.environ, CALENDAR_CARD_SHOT=str(shot))
            result = subprocess.run([str(PROBE)], capture_output=True, text=True,
                                    timeout=180, env=env)
            self.assertIn("saved", result.stdout,
                          f"probe did not render:\n{result.stdout}\n{result.stderr}")
            self.assertTrue(shot.exists(), "no screenshot produced")

            layout = re.search(r"\[CalendarCard\] layout (.+)", result.stdout)
            self.assertIsNotNone(layout, f"no layout line:\n{result.stdout}")
            boxes = [tuple(int(n) for n in box.split(","))
                     for box in layout.group(1).split()]
            self.assertEqual([(w, h) for _, _, w, h in boxes], EXPECTED_BOXES,
                             "the widget's box comes from the card it composes")

            # The grabbed field is not white, so a shadow is darker than the
            # FIELD rather than darker than zero. Measured: field 12.0, rest
            # 17.5, dragged 35.5 - and a card with `shadowEnabled: false`
            # measures the field exactly, which is what an absolute floor of
            # "greater than 6" passed on before this line existed.
            band = re.search(r"\[CalendarCard\] baseline (\S+)", result.stdout)
            self.assertIsNotNone(band, f"no baseline line:\n{result.stdout}")
            x, y, width, height = (int(n) for n in band.group(1).split(","))
            field = darkness(shot, f"{width}x{height}+{x}+{y}")

            rest = darkness_below(shot, *boxes[2]) - field
            dragged = darkness_below(shot, *boxes[3]) - field
            self.assertGreater(rest, 2.5,
                               f"the card casts no shadow at rest ({rest:.1f} "
                               f"over a field of {field:.1f})")
            self.assertGreater(dragged, rest * 1.5,
                               f"the card did not lift when handled "
                               f"(rest {rest:.1f}, dragged {dragged:.1f})")


if __name__ == "__main__":
    unittest.main()
