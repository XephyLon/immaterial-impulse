#!/usr/bin/env python3
"""Edit Mode's desktop, scored in pixels: the shrink, the corner, the substrate.

`EditModeLookProbe.qml` re-declares the mode's four-sibling arrangement under a
headless weston and saves four frames - before the mode, settled in it, held
half way in, and after leaving it. This module scores them. The split is forced
rather than chosen: `ItemGrabResult.image` is a QImage and a QImage is not
scriptable from QML, so the analysis lives outside, the same way
`test_card_shadow.py` runs.

Four things are checked here and nowhere else, because each of them is a
question about pixels that reads as correct in every source file:

- **the chrome stands down completely on exit.** The frame taken before the mode
  was ever entered and the frame taken after leaving it must be the same
  picture. A property assertion cannot say this: an inactive Loader and a zeroed
  radius are exactly what a still-transformed viewport also reports, and a
  radius or a shadow left applied to the live desktop is the failure that
  matters most - it is on screen for the rest of the session.
- **the picture's corner is cut, and a widget's corner is not.** QML has no
  rounded clip, so the corner is made by covering it with the blurred backdrop,
  and whether the cover landed on the corner is a question about one pixel. The
  probe pins an opaque marker to the wallpaper viewport's top-left corner, so
  the answer does not depend on the wallpaper: at rest the card's corner pixel
  IS the marker, in the mode it is not, and a marker's width further down the
  same edge it is again. The cover sits BELOW the widget canvas, so the same
  question asked of a widget must come back the other way - a second opaque
  block is pinned to the canvas's bottom-left corner (where this machine's own
  store keeps `visualizer`) and its corner pixel must survive. That pair is the
  whole of "there shouldn't be any clipping": one of them has to be cut and the
  other has to not be, and a cover at the wrong z reverses exactly one of them.
- **the lattice arrives with the drag rather than with the mode.** Three frames,
  because the failure is a state and not a value: in the mode at rest there are
  no lines, mid-drag there are, and the frame after the drag ends is the same
  picture as the one before it started - which is the only form of "it went away
  again" that a leftover half-faded lattice cannot pass.
- **the lattice is a substrate.** The desktop widgets arrive as external
  children of the canvas, so nothing in `WidgetCanvas.qml` decides whether they
  are drawn over the grid - the order is a consequence of when each Repeater's
  model filled. An opaque widget must hide every line under it.
- **the shrink is concentric, on the frames nobody looks at.** A viewport that
  reserved the drawer's width inside its resting geometry scaled about the
  top-left and slid, and it settled somewhere plausible - which is what let it
  ship. The desktop's position is measured off the drawn marker at half
  progress, not read back out of the function that placed it.
- **the chrome is drawn where its geometry says it is, and outside the desktop
  it frames.** The harness asserts the toolbar's and the tab bar's numbers; this
  finds their bodies in the picture, which is the half that catches a chrome
  item that reports a position and paints somewhere else - or that reports one
  and paints nothing, which is what a toolbar whose content failed to resolve
  looks like from every property.

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
EXPECTED_CHECKS = 13

GEOMETRY = re.compile(
    r"(geometry|midGeometry): screen=([\d.]+),([\d.]+) card=([\d.]+),([\d.]+),([\d.]+),([\d.]+) "
    r"radius=([\d.]+) scale=([\d.]+) marker=([\d.]+),([\d.]+),([\d.]+),([\d.]+) "
    r"panel=([\d.]+),([\d.]+),([\d.]+),([\d.]+) "
    r"corner=([\d.]+),([\d.]+),([\d.]+),([\d.]+) "
    r"markerColor=(\S+) panelColor=(\S+) cornerColor=(\S+) "
    r"toolbar=(-?[\d.]+),(-?[\d.]+),([\d.]+),([\d.]+) "
    r"tabbar=(-?[\d.]+),(-?[\d.]+),([\d.]+),([\d.]+) chromeColor=(\S+)")


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

        self.reported = {}
        for match in GEOMETRY.finditer(self.output):
            values = match.groups()
            self.reported[values[0]] = {
                "screen": tuple(float(v) for v in values[1:3]),
                "card": tuple(float(v) for v in values[3:7]),
                "radius": float(values[7]),
                "scale": float(values[8]),
                "marker": tuple(float(v) for v in values[9:13]),
                "panel": tuple(float(v) for v in values[13:17]),
                "corner": tuple(float(v) for v in values[17:21]),
                "markerColor": _hex_to_rgb(values[21]),
                "panelColor": _hex_to_rgb(values[22]),
                "cornerColor": _hex_to_rgb(values[23]),
                "toolbar": tuple(float(v) for v in values[24:28]),
                "tabbar": tuple(float(v) for v in values[28:32]),
                "chromeColor": _hex_to_rgb(values[32]),
            }
        for tag in ("geometry", "midGeometry"):
            self.assertIn(tag, self.reported,
                          f"the harness reported no {tag}:\n{self.output}")
        settled = self.reported["geometry"]
        self.screen = settled["screen"]
        self.card = settled["card"]
        self.radius = settled["radius"]
        self.scale = settled["scale"]
        self.marker = settled["marker"]
        self.panel = settled["panel"]
        self.corner = settled["corner"]
        self.marker_rgb = settled["markerColor"]
        self.panel_rgb = settled["panelColor"]
        self.corner_rgb = settled["cornerColor"]
        self.toolbar = settled["toolbar"]
        self.tabbar = settled["tabbar"]
        self.chrome_rgb = settled["chromeColor"]

        self.frames = {}
        for name in ("rest", "editing", "dragging", "released", "midway", "after"):
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

    def test_the_transform_returns_the_desktop_to_its_own_coordinates(self):
        # The other half of standing down, and the half the frame comparison
        # above cannot see: both frames are taken at progress 0, so a transform
        # whose identity is not the identity is wrong in both of them equally.
        # The marker is 220 canvas pixels square at the canvas's origin, so at
        # rest its edge is at exactly 220 - and a scale of 0.98 or an offset of
        # a few pixels left over moves it.
        edge = round(self.marker[2])
        for name in ("rest", "after"):
            frame = self.frames[name]
            self.assertEqual(frame.getpixel((edge - 2, edge - 2)), self.marker_rgb,
                             f"{name}: the desktop is not drawn at its own scale")
            self.assertNotEqual(frame.getpixel((edge + 2, edge + 2)), self.marker_rgb,
                                f"{name}: the desktop is not drawn at its own scale")

    # ---- the shrink is concentric ----------------------------------------

    def test_the_desktop_shrinks_about_dead_centre_mid_animation(self):
        # The correction this exists for is about the frames nobody looks at.
        # A viewport that reserved the drawer's width on one side scaled about
        # the top-left and slid, so at half progress the desktop sat hard
        # against one edge - and it settled somewhere plausible, which is what
        # made it survive. Measured off the drawn marker rather than read back
        # out of the same function that positions it.
        mid = self.reported["midGeometry"]
        frame = self.frames["midway"]
        screen_w, screen_h = mid["screen"]
        marker_rgb = mid["markerColor"]

        # Past the rounded corner on both axes, so the arc cannot decide where
        # the marker is judged to start.
        probe_y = round(mid["card"][1] + mid["radius"] * 2)
        probe_x = round(mid["card"][0] + mid["radius"] * 2)

        row = [x for x in range(round(screen_w)) if frame.getpixel((x, probe_y)) == marker_rgb]
        column = [y for y in range(round(screen_h)) if frame.getpixel((probe_x, y)) == marker_rgb]
        self.assertTrue(row and column, "the desktop is not drawn mid-animation at all")

        # The marker is a known square at the canvas's origin, so its drawn
        # width is the scale the desktop is really being painted at. Measured to
        # a pixel over 220, so it is worth a couple of percent and no more -
        # enough to say "this is the transform that was reported" and not enough
        # to locate the desktop's far edge, which is what the reported scale is
        # for below.
        drawn_scale = (row[-1] - row[0] + 1) / mid["marker"][2]
        self.assertAlmostEqual(drawn_scale, mid["scale"], delta=0.02)
        # ...and it is genuinely mid-flight, or this is the settled check again.
        self.assertGreater(drawn_scale, self.scale + 0.01)
        self.assertLess(drawn_scale, 0.99)

        # The origin comes from the marker's FAR edges, which are in the middle
        # of the card with nothing drawn over them. Not its leading ones: those
        # sit exactly on the card's edge, where the glass bevel's inner
        # highlight is painted across them, so the first pixel that is exactly
        # the marker's colour is a couple inside it. A centre used to cancel
        # that, and does not any more - the bias is on the leading side only
        # and it put this check 3.05px outside a 3px tolerance, which is the
        # instrument moving rather than the desktop.
        left = row[-1] + 1 - mid["marker"][2] * mid["scale"]
        top = column[-1] + 1 - mid["marker"][3] * mid["scale"]
        right = left + screen_w * mid["scale"]
        bottom = top + screen_h * mid["scale"]
        self.assertAlmostEqual(left, mid["card"][0], delta=2)
        self.assertAlmostEqual(top, mid["card"][1], delta=2)
        # Three pixels: an edge measured off a scaled, antialiased marker is
        # good to about one, and the symmetry doubles that. The failure this
        # guards is a scale about the top-left, which puts the error at the
        # width of a whole margin - 60px here - not at three.
        self.assertAlmostEqual(left, screen_w - right, delta=3,
                               msg="the desktop is not centred horizontally mid-animation")
        self.assertAlmostEqual(top, screen_h - bottom, delta=3,
                               msg="the desktop is not centred vertically mid-animation")

    # ---- the chrome ------------------------------------------------------

    def _body_span(self, frame, rect):
        """The horizontal extent of a chrome body, found in the picture.

        Read across the item's own vertical centre, where a stadium's ends are
        at their widest and the corner arc cannot decide where the body starts.
        Matched on the toolbar's surface colour with a small tolerance rather
        than on "not the background": a `Toolbar` draws a soft shadow outside
        its own bounds, and a strict inequality against the backdrop measures
        the shadow's reach instead of the body's.
        """
        x, y, w, h = rect
        row = round(y + h / 2)
        xs = [px for px in range(frame.width)
              if max(abs(a - b) for a, b in
                     zip(frame.getpixel((px, row)), self.chrome_rgb)) <= 12]
        return xs

    def test_the_chrome_is_drawn_where_its_geometry_says_it_is(self):
        # The harness asserts the numbers; this asserts the paint. A toolbar
        # whose content fails to resolve - a missing import, a Translation that
        # is not in scope - still reports a position, a size and a full set of
        # passing geometry checks, and draws a stub. Found exactly that way.
        frame = self.frames["editing"]
        for name, rect in (("toolbar", self.toolbar), ("tab bar", self.tabbar)):
            xs = self._body_span(frame, rect)
            self.assertTrue(xs, f"the {name}'s body is not in the picture at all")
            drawn_x, drawn_width = xs[0], xs[-1] - xs[0] + 1
            self.assertAlmostEqual(
                drawn_x, rect[0], delta=2,
                msg=f"the {name} is drawn {drawn_x - rect[0]:.0f}px from where it reports")
            self.assertAlmostEqual(
                drawn_width, rect[2], delta=3,
                msg=f"the {name} is drawn {drawn_width:.0f}px wide and reports {rect[2]:.0f}")

    # Deliberately NOT repeated here: whether the chrome sits outside the card
    # and inside the screen. The harness asserts that against the same live
    # rects, and a copy of it in this file would read those rects back out of
    # the harness's own report - two checks that agree by construction, which
    # is one check and a false sense of two.

    # ---- the corner ------------------------------------------------------

    def test_the_cards_corner_is_cut_out_of_the_picture(self):
        inset = 3
        corner = (round(self.card[0]) + inset, round(self.card[1]) + inset)
        # Far enough down the same edge to be past the arc, and still well
        # inside the marker, which is 220 canvas pixels tall.
        below = (round(self.card[0]) + inset, round(self.card[1] + self.radius * 2))

        self.assertEqual(self.frames["editing"].getpixel(below), self.marker_rgb,
                         "the picture does not reach the card's edge at all")
        self.assertNotEqual(self.frames["editing"].getpixel(corner), self.marker_rgb,
                            "the card's corner is square: the picture reaches it")

    def test_but_a_widget_at_that_corner_is_drawn_whole(self):
        # The maintainer's report, and the other half of the check above. The
        # cover that rounds the picture used to sit over everything, and the
        # desktop scales about its own centre - so the canvas's edge lands on
        # the card's edge and a widget parked against it is flush with the
        # rounding. At a corner that took a bite out of the widget: measured at
        # 5120x1440 before the fix, 20px along each edge and 10px on the
        # diagonal of a block pinned to the desktop's corner.
        #
        # The widget is pinned to the canvas's BOTTOM-left, so its own corner is
        # (x, y + h) and not (x, y) - reading the wrong end of it samples the
        # middle of the card's left edge, which is straight and was never cut.
        # The first version of this check did exactly that and passed on a frame
        # whose widget was visibly still being bitten.
        x, y, w, h = self.corner
        for dx, dy, where in ((2, -2, "its corner"), (2, -10, "just above it"),
                              (10, -2, "just along from it")):
            point = self.on_card(x + dx, y + h + dy)
            self.assertEqual(
                self.frames["editing"].getpixel(point), self.corner_rgb,
                f"the card's rounding is eating a widget placed in the corner, at {where}")

    # ---- the lattice arrives with the drag -------------------------------

    def test_the_mode_at_rest_draws_no_lattice(self):
        # Sampled on the same run of bare wallpaper the vacuity check below
        # uses, so the two are answering one question from opposite sides: on
        # the flat fixture anything that is not the wallpaper's own colour is a
        # line, and at rest in the mode there must be none of them.
        frame = self.frames["editing"]
        px, py, pw, ph = self.panel
        lines = [i for i in range(1, 120)
                 if frame.getpixel(self.on_card(px + pw * i / 120, py + ph + 60))
                 != WALLPAPER_RGB]
        self.assertEqual(lines, [], "the mode drew a lattice before anything was dragged")

    def test_and_the_lattice_leaves_when_the_drag_does(self):
        # The same shape as the rest/after comparison, one level in: both frames
        # are taken in the mode, so what can differ between them is the drag and
        # nothing else. A property assertion cannot say this - `gridVisible` is
        # false the instant the drag ends while the fade still has 150ms to run,
        # and a lattice that never finished leaving reports exactly the same
        # false.
        editing, released = self.frames["editing"], self.frames["released"]
        worst = 0
        differing = 0
        for y in range(0, editing.height, 3):
            for x in range(0, editing.width, 3):
                a, b = editing.getpixel((x, y)), released.getpixel((x, y))
                delta = max(abs(p - q) for p, q in zip(a, b))
                if delta:
                    differing += 1
                    worst = max(worst, delta)
        self.assertEqual(
            (differing, worst), (0, 0),
            "the drag left something on the desktop behind it: "
            f"{differing} sampled pixels differ, worst by {worst}/255")

    def test_the_corner_is_only_cut_while_the_mode_is_on(self):
        # The other half of the check above, and what stops it passing on a
        # desktop that simply is not where the geometry says it is: at rest the
        # card is the whole screen and its corner is the marker's own pixel.
        self.assertEqual(self.frames["rest"].getpixel((3, 3)), self.marker_rgb)
        self.assertEqual(self.frames["after"].getpixel((3, 3)), self.marker_rgb)

    # ---- the substrate ---------------------------------------------------

    def test_the_lattice_is_drawn_under_the_widgets_and_not_over_them(self):
        frame = self.frames["dragging"]
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
        frame = self.frames["dragging"]
        px, py, pw, ph = self.panel
        lines = 0
        for i in range(1, 120):
            point = self.on_card(px + pw * i / 120, py + ph + 60)
            if frame.getpixel(point) != WALLPAPER_RGB:
                lines += 1
        self.assertGreater(lines, 0, "no lattice was drawn, so hiding it proves nothing")


if __name__ == "__main__":
    unittest.main()
