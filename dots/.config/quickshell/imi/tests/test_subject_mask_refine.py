#!/usr/bin/env python3
"""Pins for the crisp-mask refinement in scripts/background/subject_mask.py.

The salient path squashes the whole wallpaper to the model's 1024 square, so on
a 5760x2318 wallpaper every mask texel covers ~5.6 picture pixels and the
stored mask was that raw soft matte, upscaled bilinearly by Qt. Measured on
that wallpaper: hair claimed a band of background around it, and a striped
wall behind a hairline came through as subject. Three pieces of arithmetic fix
it, and all three are testable without a model:

- the crop the second pass runs on (bbox of the first pass, padded), and the
  guard that skips it when the subject already fills the frame;
- the hardening curve applied at the end;
- the size the mask is stored at (aspect-true, 4096 long side, never larger
  than the wallpaper).

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


class RefineBoxTest(unittest.TestCase):
    """The crop the second pass runs on, in the wallpaper's own pixels."""
    def setUp(self):
        needs_numpy(self)

    def coarse(self, x0, x1, y0, y1, side=64):
        import numpy as np
        mask = np.zeros((side, side), np.float32)
        mask[y0:y1, x0:x1] = 1.0
        return mask

    def test_the_box_is_the_subject_scaled_to_the_wallpaper_and_padded(self):
        # A subject over columns 16-31 and rows 32-47 of a 64-texel mask, on a
        # 640x320 wallpaper: x spans 160-320, y spans 160-240 before padding.
        box = subject_mask.refine_box(self.coarse(16, 32, 32, 48), 640, 320, pad=0.0)
        self.assertEqual(box, (160, 160, 320, 240))
        padded = subject_mask.refine_box(self.coarse(16, 32, 32, 48), 640, 320, pad=0.5)
        # Half the width (80) each side in x, half the height (40) in y.
        self.assertEqual(padded, (80, 120, 400, 280))

    def test_the_padding_stops_at_the_frame(self):
        box = subject_mask.refine_box(self.coarse(0, 8, 56, 64), 640, 320, pad=1.0)
        self.assertEqual(box[0], 0)
        self.assertEqual(box[3], 320)
        self.assertGreaterEqual(box[1], 0)
        self.assertLessEqual(box[2], 640)

    def test_an_empty_mask_has_no_box(self):
        import numpy as np
        self.assertIsNone(subject_mask.refine_box(np.zeros((64, 64), np.float32), 640, 320))

    def test_the_default_padding_is_the_measured_one(self):
        # 12% each side is what the prototype was measured with; a smaller pad
        # cuts hair at the crop's edge, a larger one hands the second pass the
        # background the first pass was already wrong about.
        self.assertAlmostEqual(subject_mask.REFINE_PAD, 0.12)


class RefineGuardTest(unittest.TestCase):
    """Pass 2 is skipped when it cannot gain anything.

    A crop that covers ~85% of the frame is the same picture at the same
    squash, so the second run costs 0.48s and changes nothing.
    """
    def test_a_small_subject_is_refined(self):
        self.assertTrue(subject_mask.refine_wanted((100, 100, 700, 500), 1920, 1080))

    def test_a_subject_filling_the_frame_is_not(self):
        self.assertFalse(subject_mask.refine_wanted((0, 0, 1920, 1080), 1920, 1080))
        # Just under the whole frame is still the whole frame for this purpose.
        self.assertFalse(subject_mask.refine_wanted((10, 10, 1900, 1070), 1920, 1080))

    def test_the_boundary_is_the_coverage_limit(self):
        # Exactly the limit is not refined; a hair under it is.
        w, h = 1000, 1000
        limit = subject_mask.REFINE_SKIP_COVERAGE
        side_at = int((limit ** 0.5) * w)
        self.assertFalse(subject_mask.refine_wanted((0, 0, side_at + 1, side_at + 1), w, h))
        self.assertTrue(subject_mask.refine_wanted((0, 0, side_at - 20, side_at - 20), w, h))

    def test_no_box_means_nothing_to_refine(self):
        self.assertFalse(subject_mask.refine_wanted(None, 1920, 1080))


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


class WriteMaskSizeTest(unittest.TestCase):
    """`write_mask` resamples to the storage size it is handed, and stays LA."""
    def setUp(self):
        needs_numpy(self)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def write(self, mask, size):
        from PIL import Image
        path = Path(self.tmp.name) / "mask.png"
        subject_mask.write_mask(path, mask, size=size)
        with Image.open(path) as opened:
            return opened.copy()

    def test_the_file_is_the_storage_size_not_the_models(self):
        import numpy as np
        mask = np.zeros((64, 64), np.float32)
        mask[:, 32:] = 1.0
        image = self.write(mask, subject_mask.storage_size(6000, 3000))
        self.assertEqual(image.size, (4096, 2048))
        self.assertEqual(image.mode, "LA", "Qt's OpacityMask reads the alpha and "
                         "nothing else - see write_mask")

    def test_a_small_wallpaper_gets_a_mask_its_own_size(self):
        import numpy as np
        mask = np.zeros((64, 64), np.float32)
        image = self.write(mask, subject_mask.storage_size(800, 600))
        self.assertEqual(image.size, (800, 600))

    def test_no_size_keeps_the_masks_own_resolution(self):
        import numpy as np
        image = self.write(np.zeros((8, 8), np.float32), None)
        self.assertEqual(image.size, (8, 8))

    def test_the_resampled_alpha_is_still_the_mask(self):
        import numpy as np
        mask = np.zeros((64, 64), np.float32)
        mask[:, 32:] = 1.0
        image = self.write(mask, (640, 320))
        alpha = image.getchannel("A")
        self.assertEqual(alpha.getpixel((0, 0)), 0)
        self.assertEqual(alpha.getpixel((639, 319)), 255)
        self.assertEqual(alpha.tobytes(), image.getchannel("L").tobytes())


class ProducerContractTest(unittest.TestCase):
    """The producer's own path pays for none of the refinement on `status`."""
    def test_status_still_imports_nothing_heavy(self):
        import re
        source = SCRIPT.read_text()
        heavy = re.findall(r"(?m)^(?:import numpy|from PIL|import onnxruntime).*$", source)
        self.assertEqual(heavy, [], "a module-scope import makes every status query "
                         "pay for it; the refinement's imports stay inside the functions")

    def test_the_run_path_refines_and_hardens_before_writing(self):
        source = SCRIPT.read_text()
        run_body = source.split("def run(", 1)[1].split("\ndef ", 1)[0]
        self.assertIn("storage_size(", run_body)
        self.assertIn("harden(", run_body)
        segment_body = source.split("def segment(", 1)[1].split("\ndef ", 1)[0]
        self.assertIn("refine_box(", segment_body)
        self.assertIn("refine_wanted(", segment_body)

    def test_the_prompted_path_hardens_and_stores_at_the_same_size(self):
        source = SCRIPT.read_text()
        select_body = source.split("def select(", 1)[1].split("\ndef ", 1)[0]
        self.assertIn("storage_size(", select_body)
        self.assertIn("harden(", select_body)


if __name__ == "__main__":
    unittest.main()
