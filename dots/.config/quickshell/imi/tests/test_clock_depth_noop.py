#!/usr/bin/env python3
"""Depth on and depth off are the same frame when nothing sits under the layer.

The depth layer draws the wallpaper's own pixels back over the wallpaper, so
where no widget sits it is a picture drawn over itself. Turning the feature on
must therefore be a pixel-for-pixel no-op on an empty desktop, whatever the mask
contains - and any difference is the copy landing somewhere other than the region
it copies: a different crop, a different scale, or a different offset.

Why this test rather than looking: a copy that misses by a fraction of a percent
does not read as a geometry bug on screen. It reads as the wallpaper going soft,
which is how it was reported and how it was then mis-measured - two `grim`
captures minutes apart on a live desktop, with the wallpaper changed between
them, diffed as if they were an A/B. The whole value here is the control: one
process, one wallpaper nothing can swap, and only the depth flag moving.

The mask is synthetic and no model runs. Note what this deliberately does NOT
check: a mask registered to the wrong pixels still passes, because masking the
wallpaper with the wrong shape still draws the wallpaper over the wallpaper.
Mask registration is scored by test_clock_depth_compositing.py, which puts a
widget underneath and reads the occlusion boundary.
"""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tests/run_clock_depth_noop_probe.sh"

EXPECTED_CHECKS = 8

# The wallpaper's aspect (2.409) is deliberately nothing like the viewport's
# (880/247 = 3.563), so PreserveAspectCrop really crops and a copy drawn at the
# wrong scale lands somewhere visible. The probe asserts the crop happened.
WALLPAPER_SIZE = (1600, 664)

# What the invariant allows. Measured on this stack: a full-frame opaque mask
# over a 3840x1594 photograph differs by at most one least-significant bit on 0.18% of
# pixels, which is the source image making a round trip through the effect's
# intermediate buffer. A copy off by a single pixel on this fixture moves whole
# channel values, not bits.
MAX_CHANNEL_DIFF = 2
MAX_MEAN_DIFF = 0.05

PAIRS = (("off_full", "on_full"), ("off_part", "on_part"))


def _runtime_available():
    if any(shutil.which(tool) is None for tool in ("qs", "weston", "magick")):
        return False
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        return False
    return True


def write_fixtures(directory):
    """A high-frequency wallpaper and two masks that mask by ALPHA.

    Detail matters here in a way it does not for a compositing fixture: a flat
    field is identical to itself however badly it is offset, so the picture has
    to carry enough detail that a wrong crop cannot coincide with the right one.
    """
    wallpaper = directory / "wallpaper.png"
    subprocess.run(["magick", "-size", "{}x{}".format(*WALLPAPER_SIZE),
                    "-seed", "7", "plasma:fractal", str(wallpaper)],
                   check=True, timeout=60)

    from PIL import Image
    import numpy as np

    def mask(path, array):
        plane = Image.fromarray(array)
        # The same plane in both channels: Qt's OpacityMask reads the ALPHA and
        # nothing else, and keeping the luminance makes the file inspectable.
        Image.merge("LA", [plane, plane]).save(path)

    full = np.full((1024, 1024), 255, np.uint8)
    part = np.zeros((1024, 1024), np.uint8)
    part[180:900, 260:840] = 255
    mask(directory / "mask-full.png", full)
    mask(directory / "mask-part.png", part)
    return wallpaper, directory / "mask-full.png", directory / "mask-part.png"


def difference(left, right):
    from PIL import Image
    import numpy as np
    a = np.asarray(Image.open(left).convert("RGB")).astype(int)
    b = np.asarray(Image.open(right).convert("RGB")).astype(int)
    if a.shape != b.shape:
        raise AssertionError(f"{left.name} is {a.shape} and {right.name} is {b.shape}")
    delta = np.abs(a - b)
    return int(delta.max()), float(delta.mean()), float((delta.max(axis=2) > 6).mean())


@unittest.skipUnless(_runtime_available(), "needs qs, weston, magick, numpy and pillow")
class ClockDepthNoOpTest(unittest.TestCase):
    def test_turning_depth_on_over_an_empty_desktop_changes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            wallpaper, full, part = write_fixtures(tmp)
            env = dict(os.environ,
                       CLOCK_DEPTH_WALLPAPER=str(wallpaper),
                       CLOCK_DEPTH_FULL_MASK=str(full),
                       CLOCK_DEPTH_PART_MASK=str(part),
                       CLOCK_DEPTH_SHOT_DIR=str(tmp))
            result = subprocess.run([str(PROBE)], capture_output=True, text=True,
                                    timeout=180, env=env)
            output = result.stdout + result.stderr
            self.assertIn(f"[ClockDepthNoOp] checks: {EXPECTED_CHECKS} failures: 0", output,
                          f"harness did not finish cleanly:\n{output}")

            for off, on in PAIRS:
                off_shot, on_shot = tmp / f"{off}.png", tmp / f"{on}.png"
                self.assertTrue(off_shot.exists() and on_shot.exists(),
                                f"missing {off}/{on} screenshots:\n{output}")
                worst, mean, differing = difference(off_shot, on_shot)
                self.assertLessEqual(
                    worst, MAX_CHANNEL_DIFF,
                    f"drawing the subject back over its own wallpaper is not a no-op "
                    f"({off} vs {on}): worst channel difference {worst}, mean {mean:.3f}, "
                    f"{differing:.1%} of pixels differ by more than 6. The copy is not "
                    f"landing on the region it copies.")
                self.assertLessEqual(
                    mean, MAX_MEAN_DIFF,
                    f"{off} vs {on}: mean absolute difference {mean:.3f} over the frame")

            # And the mask must not leak into the frame the layer is not drawing:
            # a masked copy is either invisible or a no-op, never a third thing.
            worst, mean, _ = difference(tmp / "off_full.png", tmp / "off_part.png")
            self.assertLessEqual(worst, MAX_CHANNEL_DIFF,
                                 "the mask changed the frame while depth was off "
                                 f"(worst channel difference {worst})")


if __name__ == "__main__":
    unittest.main()
