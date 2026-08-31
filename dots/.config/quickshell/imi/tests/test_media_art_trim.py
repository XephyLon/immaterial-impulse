#!/usr/bin/env python3
"""Pins for scripts/media/art_trim.py - the letterbox probe.

Synthetic Pillow images, no fixtures: a letterboxed square must be found, a
full-bleed cover must be left alone, one moody dark edge is composition (no
symmetric pair, no trim), and bars below the floor are noise.
"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/media/art_trim.py"

sys.path.insert(0, str(SCRIPT.parent))
import art_trim  # noqa: E402

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402


def noisy_cover(width, height, seed=7):
    rng = np.random.default_rng(seed)
    return rng.integers(30, 226, size=(height, width, 3)).astype("uint8")


def save(tmp, array, name="art.png"):
    path = Path(tmp) / name
    Image.fromarray(array, "RGB").save(path)
    return path


class ArtTrimTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_letterboxed_square_is_found(self):
        art = np.zeros((360, 640, 3), dtype="uint8")
        art[:, 140:500] = noisy_cover(360, 360)
        result = art_trim.probe(save(self.tmp.name, art))
        self.assertEqual(result["top"], 0)
        self.assertEqual(result["bottom"], 0)
        self.assertAlmostEqual(result["left"], 140, delta=8)
        self.assertAlmostEqual(result["right"], 140, delta=8)

    def test_horizontal_bars_are_found(self):
        art = np.full((640, 360, 3), 250, dtype="uint8")
        art[140:500, :] = noisy_cover(360, 360)
        result = art_trim.probe(save(self.tmp.name, art))
        self.assertAlmostEqual(result["top"], 140, delta=8)
        self.assertAlmostEqual(result["bottom"], 140, delta=8)
        self.assertEqual(result["left"], 0)

    def test_a_full_bleed_cover_is_left_alone(self):
        result = art_trim.probe(save(self.tmp.name, noisy_cover(400, 400)))
        self.assertEqual((result["left"], result["top"],
                          result["right"], result["bottom"]), (0, 0, 0, 0))

    def test_one_dark_edge_is_composition_not_a_bar(self):
        art = noisy_cover(400, 400)
        art[:80, :] = 0
        result = art_trim.probe(save(self.tmp.name, art))
        self.assertEqual(result["top"], 0, "no symmetric pair, no trim")

    def test_a_sliver_below_the_floor_is_noise(self):
        art = noisy_cover(400, 400)
        art[:4, :] = 0
        art[-4:, :] = 0
        result = art_trim.probe(save(self.tmp.name, art))
        self.assertEqual((result["top"], result["bottom"]), (0, 0))

    def test_the_cli_answers_json_and_reports_failures(self):
        art = save(self.tmp.name, noisy_cover(64, 64))
        out = subprocess.run([sys.executable, str(SCRIPT), str(art)],
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 0)
        self.assertEqual(json.loads(out.stdout)["width"], 64)
        bad = subprocess.run([sys.executable, str(SCRIPT), "/no/such/file"],
                             capture_output=True, text=True)
        self.assertEqual(bad.returncode, 1)
        self.assertIn("error", json.loads(bad.stdout))


if __name__ == "__main__":
    unittest.main()
