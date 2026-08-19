#!/usr/bin/env python3
"""Pins for the crisp-mask refinement in scripts/background/subject_mask.py.

The salient path squashes the whole wallpaper to the model's 1024 square, so
on a 5760x2318 wallpaper every mask texel covers ~5.6 picture pixels and the
stored mask was that raw soft matte, upscaled bilinearly by Qt. Measured on
that wallpaper: hair claimed a band of background around it, and a striped
wall behind a hairline came through as subject - the soft band, upscaled. Two
pieces of arithmetic fix it, and both are testable without a model:

- the hardening curve, applied AFTER the mask is resampled to its storage
  size, so the edge is ~1 storage pixel rather than a bilinear ramp;
- the size the mask is stored at (aspect-true, 4096 long side, never larger
  than the wallpaper).

A second model pass over the subject's box was here too, and was measured out
again (see `segment`'s docstring); its tests went with it.

Pure numpy and Pillow, no ONNX session - `test_clock_depth_cache.py` pins that
`status` never constructs one, and nothing here may loosen that.
"""
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/background/subject_mask.py"

sys.path.insert(0, str(SCRIPT.parent))
import subject_mask  # noqa: E402


def needs_numpy(test):
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        test.skipTest("needs numpy and pillow (the shell's uv venv)")


class HardenTest(unittest.TestCase):
    """The sigmoid that turns the model's soft matte into an edge.

    Measured on the Violet Evergarden wallpaper: the band of pixels between
    0.16 and 0.84 went from 0.496 Mpx to 0.235 Mpx under this curve. What is
    pinned is the shape, not the number - 0.5 stays put (so the subject's
    boundary does not move), the curve is monotonic (so no pixel changes sides),
    and it does not clip (so the file's alpha stays a smooth ramp rather than a
    step, which is what reads as a sticker).
    """
    def setUp(self):
        needs_numpy(self)

    def test_the_boundary_stays_at_a_half(self):
        import numpy as np
        out = subject_mask.harden(np.array([0.5], np.float32))
        self.assertAlmostEqual(float(out[0]), 0.5, places=6)

    def test_the_curve_is_monotonic_and_stays_inside_the_unit_range(self):
        import numpy as np
        ramp = np.linspace(0.0, 1.0, 1001, dtype=np.float32)
        out = subject_mask.harden(ramp)
        self.assertTrue(np.all(np.diff(out) > 0), "a pixel must never change sides")
        self.assertGreaterEqual(float(out.min()), 0.0)
        self.assertLessEqual(float(out.max()), 1.0)

    def test_the_curve_is_steeper_than_the_identity_at_the_boundary(self):
        import numpy as np
        near = subject_mask.harden(np.array([0.4, 0.6], np.float32))
        self.assertLess(float(near[0]), 0.4)
        self.assertGreater(float(near[1]), 0.6)

    def test_the_ends_are_pulled_to_the_rails(self):
        import numpy as np
        ends = subject_mask.harden(np.array([0.0, 1.0], np.float32))
        self.assertLess(float(ends[0]), 0.01)
        self.assertGreater(float(ends[1]), 0.99)


class StorageSizeTest(unittest.TestCase):
    """The size a mask is written at: 4096 on the long side, aspect kept."""
    def test_a_wide_wallpaper_is_stored_at_4096_wide(self):
        self.assertEqual(subject_mask.storage_size(5760, 2318), (4096, 1648))

    def test_a_tall_wallpaper_is_stored_at_4096_tall(self):
        self.assertEqual(subject_mask.storage_size(2160, 7680), (1152, 4096))

    def test_a_small_wallpaper_is_never_upsampled(self):
        self.assertEqual(subject_mask.storage_size(1920, 1080), (1920, 1080))
        self.assertEqual(subject_mask.storage_size(4096, 1024), (4096, 1024))

    def test_the_aspect_survives(self):
        w, h = subject_mask.storage_size(7680, 2160)
        self.assertAlmostEqual(w / h, 7680 / 2160, places=2)

    def test_a_wallpaper_with_no_size_is_refused(self):
        with self.assertRaises(ValueError):
            subject_mask.storage_size(0, 100)


class PrepareMaskTest(unittest.TestCase):
    """`prepare_mask` resamples to the storage size and hardens AFTER that.

    The order is what makes the stored edge ~1 pixel: a bilinear upsample of an
    already-hardened edge is a ramp as wide as the scale factor, which is the
    band the hardening exists to remove. Measured on the Violet Evergarden
    wallpaper: soft band 0.112 Mpx this way round, 0.235 the other.
    """
    def setUp(self):
        needs_numpy(self)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def step(self, side=64):
        import numpy as np
        mask = np.zeros((side, side), np.float32)
        mask[:, side // 2:] = 1.0
        return mask

    def written(self, mask, size):
        from PIL import Image
        path = Path(self.tmp.name) / "mask.png"
        subject_mask.write_mask(path, subject_mask.prepare_mask(mask, size))
        with Image.open(path) as opened:
            return opened.copy()

    def test_the_file_is_the_storage_size_not_the_models(self):
        image = self.written(self.step(), subject_mask.storage_size(6000, 3000))
        self.assertEqual(image.size, (4096, 2048))
        self.assertEqual(image.mode, "LA", "Qt's OpacityMask reads the alpha and "
                         "nothing else - see write_mask")

    def test_a_small_wallpaper_gets_a_mask_its_own_size(self):
        image = self.written(self.step(), subject_mask.storage_size(800, 600))
        self.assertEqual(image.size, (800, 600))

    def test_write_mask_itself_keeps_the_masks_own_resolution(self):
        import numpy as np
        from PIL import Image
        path = Path(self.tmp.name) / "raw.png"
        subject_mask.write_mask(path, np.zeros((8, 8), np.float32))
        with Image.open(path) as opened:
            self.assertEqual(opened.size, (8, 8))

    def test_the_resampled_alpha_is_still_the_mask(self):
        image = self.written(self.step(), (640, 320))
        alpha = image.getchannel("A")
        # The rails after k=6 hardening are 0.0025 and 0.9975, i.e. 1 and 254
        # in the file - hardening never quite reaches the ends, by design.
        self.assertLessEqual(alpha.getpixel((0, 0)), 1)
        self.assertGreaterEqual(alpha.getpixel((639, 319)), 254)
        self.assertEqual(alpha.tobytes(), image.getchannel("L").tobytes())

    def test_the_edge_is_hardened_after_the_upsample_not_before(self):
        """A step upsampled 8x bilinearly is a ramp eight pixels wide, four of
        them between 0.25 and 0.75. Hardening THEN upsampling keeps all four
        (0.313, 0.438, 0.562, 0.687); upsampling THEN hardening (k=6) leaves
        two (0.321, 0.679) with the rest pulled to the rails."""
        import numpy as np

        def mid_band(row):
            return int(((row > 0.25) & (row < 0.75)).sum())

        row = subject_mask.prepare_mask(self.step(16), (128, 128))[8]
        control = subject_mask.resample(subject_mask.harden(self.step(16)), (128, 128))[8]
        self.assertGreaterEqual(mid_band(control), 4, "the control must carry the "
                                "ramp, or this test cannot tell the two orders apart")
        self.assertLessEqual(mid_band(row) * 2, mid_band(control),
                        f"{mid_band(row)} mid-band pixels against {mid_band(control)} "
                        "for harden-then-resample - the hardening must run after "
                        "the resample")
        # And the ramp as a whole is pulled in, not just its middle: distance
        # from the rails summed across the row (measured 1.19 against 2.31).
        softness = float(np.minimum(row, 1.0 - row).sum())
        control_softness = float(np.minimum(control, 1.0 - control).sum())
        self.assertLess(softness, 0.7 * control_softness)
        self.assertTrue(np.all(np.diff(row) >= 0), "the edge is still one edge")


class ProducerContractTest(unittest.TestCase):
    """The producer's own path pays for none of the refinement on `status`."""
    def test_status_still_imports_nothing_heavy(self):
        import re
        source = SCRIPT.read_text()
        heavy = re.findall(r"(?m)^(?:import numpy|from PIL|import onnxruntime).*$", source)
        self.assertEqual(heavy, [], "a module-scope import makes every status query "
                         "pay for it; the refinement's imports stay inside the functions")

    def test_the_run_path_hardens_and_sizes_before_writing(self):
        source = SCRIPT.read_text()
        run_body = source.split("def run(", 1)[1].split("\ndef ", 1)[0]
        self.assertIn("prepare_mask(", run_body)
        self.assertIn("storage_size(", run_body)

    def test_the_prompted_path_hardens_and_stores_at_the_same_size(self):
        source = SCRIPT.read_text()
        select_body = source.split("def select(", 1)[1].split("\ndef ", 1)[0]
        self.assertIn("prepare_mask(", select_body)
        self.assertIn("storage_size(", select_body)

    def test_prepare_mask_is_the_only_place_the_order_is_decided(self):
        source = SCRIPT.read_text()
        body = source.split("def prepare_mask(", 1)[1].split("\ndef ", 1)[0]
        self.assertIn("harden(resample(", body.replace(" ", ""),
                      "prepare_mask must resample first and harden second")


if __name__ == "__main__":
    unittest.main()
