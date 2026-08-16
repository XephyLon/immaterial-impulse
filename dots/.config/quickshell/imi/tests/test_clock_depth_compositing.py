#!/usr/bin/env python3
"""Does the depth layer put the wallpaper over the clock, and follow the pan?

The layer is a fourth sibling of the wallpaper viewport that reconstructs the
pan by hand, and both halves of that are invisible everywhere else: source text
cannot show whether the mask lands on the pixels it was cut from, and
qmltestrunner draws no layer effect, so nothing but a rendered frame can answer
it. lint_clock_depth_geometry.py pins the declaration; this pins what it draws.

The mask is synthetic - a half-white 1024x1024 square over a flat wallpaper -
so no model runs here and no judgement about any mask's quality is involved.

The pan assertion is the reason this exists at all. A layer bound to the pan's
DESTINATION instead of to the viewport's live x settles in exactly the right
place, so every settled check passes on it; only a frame taken while the 600ms
animation is running can tell the two apart.
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tests/run_clock_depth_probe.sh"

EXPECTED_CHECKS = 13

# Fixture geometry, and the arithmetic the assertions rest on. The wallpaper is
# 2:1 into a 2:1 viewport, so the picture fills the box exactly and the mask's
# normalised coordinates map straight onto viewport pixels.
WALLPAPER_SIZE = (2000, 1000)
VIEWPORT = (1000, 500)
MASK_SPLIT = 0.5          # the mask is opaque from here rightwards
CLOCK_BAND = (160, 240)   # the y range the stand-in clock occupies
PAN_DISTANCE = 200        # the pan, leftwards

WALLPAPER_RGB = (0x00, 0x40, 0xff)
CLOCK_RGB = (0xff, 0x20, 0x20)


def _runtime_available():
    return all(shutil.which(tool) is not None for tool in ("qs", "weston", "magick"))


def write_fixtures(directory):
    wallpaper = directory / "wallpaper.png"
    mask = directory / "mask.png"
    subprocess.run(["magick", "-size", "{}x{}".format(*WALLPAPER_SIZE),
                    "xc:#%02x%02x%02x" % WALLPAPER_RGB, str(wallpaper)],
                   check=True, timeout=60)
    # Opaque white from the midline rightwards, transparent to the left. The
    # ALPHA is what masks - Qt's OpacityMask reads nothing else, and a mask that
    # is opaque black on the left would let the whole wallpaper through, which
    # is the bug this fixture is shaped to catch. The model's own output is a
    # square covering the whole picture, so the mask's aspect is deliberately
    # not the wallpaper's.
    subprocess.run(["magick", "-size", "1024x1024", "xc:none", "-fill", "white",
                    "-draw", "rectangle 512,0 1023,1023", str(mask)],
                   check=True, timeout=60)
    return wallpaper, mask


def pixel(shot, x, y):
    out = subprocess.run(["magick", str(shot), "-format",
                          "%[pixel:p{" + f"{x},{y}" + "}]", "info:"],
                         capture_output=True, text=True, timeout=60).stdout.strip()
    numbers = [int(n) for n in re.findall(r"\d+", out)[:3]]
    if len(numbers) < 3:
        raise AssertionError(f"could not read pixel {x},{y}: {out!r}")
    return tuple(numbers)


def close_to(got, want, tolerance=24):
    return all(abs(a - b) <= tolerance for a, b in zip(got, want))


def boundary_x(shot, y, search_from, search_to):
    """The x at which the clock stops being visible along a row.

    Scanned rather than computed because the whole question is where the layer
    actually drew, and a computed answer would only restate the expectation.
    """
    last_clock = None
    for x in range(search_from, search_to):
        if close_to(pixel(shot, x, y), CLOCK_RGB):
            last_clock = x
    return last_clock


@unittest.skipUnless(_runtime_available(), "needs qs, weston and magick on PATH")
class ClockDepthCompositingTest(unittest.TestCase):
    def test_the_subject_covers_the_clock_and_travels_with_the_wallpaper(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            wallpaper, mask = write_fixtures(tmp)
            shots = {name: tmp / f"{name}.png" for name in ("rest", "pan", "flat")}
            env = dict(os.environ,
                       CLOCK_DEPTH_WALLPAPER=str(wallpaper),
                       CLOCK_DEPTH_MASK=str(mask),
                       CLOCK_DEPTH_REST_SHOT=str(shots["rest"]),
                       CLOCK_DEPTH_PAN_SHOT=str(shots["pan"]),
                       CLOCK_DEPTH_FLAT_SHOT=str(shots["flat"]))
            result = subprocess.run([str(PROBE)], capture_output=True, text=True,
                                    timeout=180, env=env)
            output = result.stdout + result.stderr
            self.assertIn(f"[ClockDepth] checks: {EXPECTED_CHECKS} failures: 0", output,
                          f"harness did not finish cleanly:\n{output}")
            for name, shot in shots.items():
                self.assertTrue(shot.exists(), f"no {name} screenshot produced:\n{output}")

            row = (CLOCK_BAND[0] + CLOCK_BAND[1]) // 2

            # At rest: the masked half of the wallpaper is drawn back over the
            # clock, the unmasked half is not. This is the effect.
            masked_x = int(VIEWPORT[0] * MASK_SPLIT) + 120
            unmasked_x = int(VIEWPORT[0] * MASK_SPLIT) - 120
            self.assertTrue(close_to(pixel(shots["rest"], masked_x, row), WALLPAPER_RGB),
                            "inside the mask the clock should be behind the wallpaper, "
                            f"got {pixel(shots['rest'], masked_x, row)}")
            self.assertTrue(close_to(pixel(shots["rest"], unmasked_x, row), CLOCK_RGB),
                            "outside the mask the clock should be on top, "
                            f"got {pixel(shots['rest'], unmasked_x, row)}")

            # No mask: exactly today's rendering, with the clock flat on top
            # everywhere. A wrong mask is a visible defect; a missing one must
            # not be.
            for x in (unmasked_x, masked_x):
                self.assertTrue(close_to(pixel(shots["flat"], x, row), CLOCK_RGB),
                                "with no mask the clock must be drawn flat on top, "
                                f"got {pixel(shots['flat'], x, row)} at x={x}")

            # Mid-pan: the occlusion boundary has moved with the wallpaper, and
            # has NOT arrived at the pan's destination. A layer bound to
            # bgRoot.parallaxOffsets would already be at the far end here, and
            # a layer that did not follow at all would still be at rest.
            rest_edge = boundary_x(shots["rest"], row, 0, 700)
            pan_edge = boundary_x(shots["pan"], row, 0, 700)
            self.assertIsNotNone(rest_edge, "no occlusion boundary at rest")
            self.assertIsNotNone(pan_edge, "no occlusion boundary mid-pan")
            travelled = rest_edge - pan_edge
            self.assertGreater(travelled, 20,
                               "the depth layer did not follow the pan at all "
                               f"(rest={rest_edge} pan={pan_edge})")
            self.assertLess(travelled, PAN_DISTANCE - 20,
                            "the depth layer arrived at the pan's destination in one "
                            "frame - it is bound to the target, not to the viewport "
                            f"(rest={rest_edge} pan={pan_edge})")


if __name__ == "__main__":
    unittest.main()
