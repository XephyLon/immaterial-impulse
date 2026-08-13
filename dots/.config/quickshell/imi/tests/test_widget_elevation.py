#!/usr/bin/env python3
"""The five widgets that were never cards, measured in pixels.

`test_card_shadow.py` renders three WidgetCards. These five - the cookie
clock, the pixel clock, the shape-masked image, the user card and the world
clock - each carried their own `StyledDropShadow` at their own radius, colour
and alpha, and are folded onto `Appearance.elevation` through
`WidgetElevation`. A structure test can only see that the wiring is spelled
correctly, so this renders the real widgets under headless weston.

Each widget is rendered three times side by side: at rest, handled, and with
its elevation suppressed. The three cells are identical apart from the shadow,
so the shadow is exactly what a cell differs from the suppressed one BY - which
means the measurement needs no per-widget geometry and works the same for a
cookie, a punched glyph grid and a rounded card. A widget that lost its
elevation reads as zero against its own suppressed twin; before this landed,
every one of them did.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROBE = ROOT / "tests/run_widget_elevation_probe.sh"

# Kept in step with WidgetElevationProbe.qml, which prints all of it.
SPECIMENS = (("clock", 40, 230, 230), ("pixel-clock", 340, 276, 252),
             ("custom-image", 640, 200, 200), ("user-card", 940, 276, 228),
             ("world-clock", 1240, 276, 228))
COLUMNS = {"rest": 40, "handled": 360, "still": 680}
# The elevation's own bleed: how far outside its box a body's shadow reaches.
BLEED = 28


def darkening(shot, specimen, column):
    """How much darker a cell is than the same widget with no elevation.

    ImageMagick does the arithmetic and the averaging: piping raw grey out of
    it and summing by hand produced values that did not match the visible
    image at all. The operand order is the one that yields the darkening -
    established by measurement, and self-checking, since the suppressed column
    compared against itself must come out at exactly zero either way.
    """
    _, top, width, height = specimen
    region = f"{width + BLEED * 2}x{height + BLEED * 2}"
    cell = f"{region}+{COLUMNS[column] - BLEED}+{top - BLEED}"
    reference = f"{region}+{COLUMNS['still'] - BLEED}+{top - BLEED}"
    with tempfile.NamedTemporaryFile(suffix=".png") as difference:
        subprocess.run(
            ["magick",
             "(", str(shot), "-crop", cell, "+repage", ")",
             "(", str(shot), "-crop", reference, "+repage", ")",
             "-compose", "Minus", "-composite",
             "-colorspace", "Gray", difference.name],
            check=True, timeout=60)
        mean = subprocess.run(
            ["magick", "identify", "-format", "%[fx:mean]", difference.name],
            capture_output=True, text=True, timeout=60).stdout.strip()
    return float(mean) * 255.0


def _runtime_available():
    # Same gate the other runtime probes use, plus the analyser: CI has no
    # compositor, and a test that hard-fails there is reporting the runner's
    # shape as a defect in the shadow.
    return all(shutil.which(tool) is not None
               for tool in ("qs", "weston", "magick"))


@unittest.skipUnless(_runtime_available(), "needs qs, weston and magick on PATH")
class WidgetElevationTest(unittest.TestCase):
    def test_every_folded_widget_casts_lifts_and_drops_its_shadow(self):
        with tempfile.TemporaryDirectory() as tmp:
            shot = Path(tmp) / "widgets.png"
            env = dict(os.environ, WIDGET_ELEVATION_SHOT=str(shot))
            result = subprocess.run([str(PROBE)], capture_output=True, text=True,
                                    timeout=240, env=env)
            self.assertIn("saved", result.stdout,
                          f"probe did not render:\n{result.stdout}\n{result.stderr}")
            self.assertTrue(shot.exists(), "no screenshot produced")

            for specimen in SPECIMENS:
                tag = specimen[0]
                measured = {column: darkening(shot, specimen, column)
                            for column in COLUMNS}
                detail = f"{tag}: " + " ".join(
                    f"{name}={value:.2f}" for name, value in measured.items())

                self.assertLess(measured["still"], 0.01,
                                f"the suppressed twin is not the reference ({detail})")
                self.assertGreater(measured["rest"], 0.5,
                                   f"a resting widget casts no shadow ({detail})")
                self.assertGreater(measured["handled"], measured["rest"] * 1.2,
                                   f"a handled widget does not lift ({detail})")


if __name__ == "__main__":
    unittest.main(verbosity=2)
