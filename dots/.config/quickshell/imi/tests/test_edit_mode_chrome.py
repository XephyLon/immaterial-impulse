#!/usr/bin/env python3
"""Edit Mode's desktop, scored in pixels: the corner, the substrate, the exit.

`EditModeLookProbe.qml` re-declares the mode's four-sibling arrangement under a
headless weston and saves three frames - before the mode, during it, and after
leaving it. This module scores them. The split is forced rather than chosen:
`ItemGrabResult.image` is a QImage and a QImage is not scriptable from QML, so
the analysis lives outside, the same way `test_card_shadow.py` runs.

Three things are checked here and nowhere else, because each of them is a
question about pixels that reads as correct in every source file:

- **the chrome stands down completely on exit.** The frame taken before the mode
  was ever entered and the frame taken after leaving it must be the same
  picture. A property assertion cannot say this: an inactive Loader and a zeroed
  radius are exactly what a still-transformed viewport also reports, and a
  radius or a shadow left applied to the live desktop is the failure that
  matters most - it is on screen for the rest of the session.
- **the desktop's corner is cut.** QML has no rounded clip, so the corner is
  made by covering it with the blurred backdrop, and whether the cover landed on
  the corner is a question about one pixel. The probe pins an opaque marker to
  the canvas's own top-left corner, so the answer does not depend on the
  wallpaper: at rest the card's corner pixel IS the marker, in the mode it is
  not, and a marker's width further down the same edge it is again.
- **the lattice is a substrate.** The desktop widgets arrive as external
  children of the canvas, so nothing in `WidgetCanvas.qml` decides whether they
  are drawn over the grid - the order is a consequence of when each Repeater's
  model filled. An opaque widget must hide every line under it.

The fixture is a flat colour so that "is this pixel a grid line" is answerable
at all; the check that the lattice is drawn in the first place is what stops the
substrate check from passing on a frame with no grid in it.

Skips when weston or qs is missing, as in CI.
"""

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNNER = Path(__file__).resolve().parent / "run_edit_mode_look_probe.sh"

SCREEN = (1600, 900)
# Flat, and nothing like the marker or the panel. A photograph would make "is
# this pixel a grid line" unanswerable, which is the one thing the vacuity check
# needs to be able to ask.
WALLPAPER_RGB = (58, 96, 140)

# The harness states how many checks it ran; this is the literal it must state.
# Read back out of its own output it would agree with itself by construction,
# and `failures: 0` is also what a harness that ran nothing prints.
EXPECTED_CHECKS = 6

GEOMETRY = re.compile(
    r"geometry: screen=([\d.]+),([\d.]+) card=([\d.]+),([\d.]+),([\d.]+),([\d.]+) "
    r"radius=([\d.]+) scale=([\d.]+) marker=([\d.]+),([\d.]+),([\d.]+),([\d.]+) "
    r"panel=([\d.]+),([\d.]+),([\d.]+),([\d.]+) markerColor=(\S+) panelColor=(\S+)")


def _available():
    return shutil.which("qs") is not None and shutil.which("weston") is not None


def _hex_to_rgb(value):
    value = value.lstrip("#")
    if len(value) == 8:  # #aarrggbb
        value = value[2:]
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


@unittest.skipUnless(_available(), "needs qs and weston on PATH")
class EditModeChromeTest(unittest.TestCase):
    def setUp(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("needs Pillow to read the frames back")
        self.Image = Image
        self.tmp = Path(tempfile.mkdtemp(prefix="imi-edit-mode-look-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

        wallpaper = self.tmp / "wallpaper.png"
        Image.new("RGB", (800, 450), WALLPAPER_RGB).save(wallpaper)

        env = dict(os.environ)
        env["EDIT_MODE_WALLPAPER"] = str(wallpaper)
        env["EDIT_MODE_SHOT_DIR"] = str(self.tmp)
        env["EDIT_MODE_WIDTH"] = str(SCREEN[0])
        env["EDIT_MODE_HEIGHT"] = str(SCREEN[1])
        result = subprocess.run(["bash", str(RUNNER)], cwd=str(ROOT), env=env,
                                capture_output=True, text=True, timeout=240)
        self.output = result.stdout + result.stderr

        self.assertNotIn("FAIL", self.output, f"the harness reported failures:\n{self.output}")
        self.assertIn(f"[EditModeLook] checks: {EXPECTED_CHECKS} failures: 0", self.output,
                      f"the harness did not finish cleanly:\n{self.output}")

        match = GEOMETRY.search(self.output)
        self.assertIsNotNone(match, f"the harness reported no geometry:\n{self.output}")
        values = match.groups()
        self.card = tuple(float(v) for v in values[2:6])
        self.radius = float(values[6])
        self.scale = float(values[7])
        self.marker = tuple(float(v) for v in values[8:12])
        self.panel = tuple(float(v) for v in values[12:16])
        self.marker_rgb = _hex_to_rgb(values[16])
        self.panel_rgb = _hex_to_rgb(values[17])

        self.frames = {}
        for name in ("rest", "editing", "after"):
            path = self.tmp / f"{name}.png"
            self.assertTrue(path.exists(), f"the harness saved no {name} frame")
            self.frames[name] = Image.open(path).convert("RGB")

    # ---- helpers ---------------------------------------------------------

    def on_card(self, x, y):
        """A point in canvas coordinates, in the frame the card is drawn at."""
        return (round(self.card[0] + x * self.scale), round(self.card[1] + y * self.scale))

    # ---- the exit --------------------------------------------------------

    def test_the_desktop_after_the_mode_is_the_desktop_before_it(self):
        rest, after = self.frames["rest"], self.frames["after"]
        self.assertEqual(rest.size, after.size)
        worst = 0
        differing = 0
        for y in range(0, rest.height, 3):
            for x in range(0, rest.width, 3):
                a, b = rest.getpixel((x, y)), after.getpixel((x, y))
                delta = max(abs(p - q) for p, q in zip(a, b))
                if delta:
                    differing += 1
                    worst = max(worst, delta)
        self.assertEqual(
            (differing, worst), (0, 0),
            "the mode left something applied to the live desktop: "
            f"{differing} sampled pixels differ, worst by {worst}/255")

    # ---- the corner ------------------------------------------------------

    def test_the_cards_corner_is_cut_out_of_the_desktop(self):
        inset = 3
        corner = (round(self.card[0]) + inset, round(self.card[1]) + inset)
        # Far enough down the same edge to be past the arc, and still well
        # inside the marker, which is 220 canvas pixels tall.
        below = (round(self.card[0]) + inset, round(self.card[1] + self.radius * 2))

        self.assertEqual(self.frames["editing"].getpixel(below), self.marker_rgb,
                         "the desktop does not reach the card's edge at all")
        self.assertNotEqual(self.frames["editing"].getpixel(corner), self.marker_rgb,
                            "the card's corner is square: the desktop reaches it")

    def test_the_corner_is_only_cut_while_the_mode_is_on(self):
        # The other half of the check above, and what stops it passing on a
        # desktop that simply is not where the geometry says it is: at rest the
        # card is the whole screen and its corner is the marker's own pixel.
        self.assertEqual(self.frames["rest"].getpixel((3, 3)), self.marker_rgb)
        self.assertEqual(self.frames["after"].getpixel((3, 3)), self.marker_rgb)

    # ---- the substrate ---------------------------------------------------

    def test_the_lattice_is_drawn_under_the_widgets_and_not_over_them(self):
        frame = self.frames["editing"]
        px, py, pw, ph = self.panel

        showing = []
        for i in range(1, 40):
            point = self.on_card(px + pw * i / 40, py + ph / 2)
            if frame.getpixel(point) != self.panel_rgb:
                showing.append(point)
        self.assertEqual(showing, [],
                         "the lattice is drawn over an opaque widget")

    def test_and_the_lattice_is_there_to_be_hidden(self):
        # Without this the check above passes on a frame with no grid in it.
        # Sampled on a run of bare wallpaper below the panel: on the flat
        # fixture, anything that is not the wallpaper's own colour is a line.
        frame = self.frames["editing"]
        px, py, pw, ph = self.panel
        lines = 0
        for i in range(1, 120):
            point = self.on_card(px + pw * i / 120, py + ph + 60)
            if frame.getpixel(point) != WALLPAPER_RGB:
                lines += 1
        self.assertGreater(lines, 0, "no lattice was drawn, so hiding it proves nothing")


if __name__ == "__main__":
    unittest.main()
