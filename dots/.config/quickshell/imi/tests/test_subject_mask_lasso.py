#!/usr/bin/env python3
"""Pins for the hand-drawn half of `select` in subject_mask.py.

A lasso is a polygon the user drew on the desktop, and everything about it is
testable without a model: the CLI grammar, the rasterised arithmetic (label 1
unions, label 0 subtracts, in draw order), the lasso-only path that never
constructs an ONNX session, and the prompt round-trip that keeps loops and
clicks in one recorded gesture.

Pure numpy and Pillow, like test_subject_mask_refine.py - nothing here may
load a model, and the lasso-only select() call is itself the proof that the
path does not need one.
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/background/subject_mask.py"

sys.path.insert(0, str(SCRIPT.parent))
import subject_mask as sm  # noqa: E402

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402


SQUARE = "1:0.25,0.25;0.75,0.25;0.75,0.75;0.25,0.75"


class ParseLassoTests(unittest.TestCase):
    def test_a_square_parses(self):
        entry = sm.parse_lasso(SQUARE)
        self.assertEqual(entry["label"], 1)
        self.assertEqual(len(entry["lasso"]), 4)
        self.assertEqual(entry["lasso"][0], [0.25, 0.25])

    def test_exclude_label_parses(self):
        self.assertEqual(sm.parse_lasso("0:0,0;1,0;1,1")["label"], 0)

    def test_no_label_refuses(self):
        with self.assertRaises(ValueError):
            sm.parse_lasso("0.25,0.25;0.75,0.25;0.75,0.75")

    def test_a_bad_label_refuses(self):
        with self.assertRaises(ValueError):
            sm.parse_lasso("2:0,0;1,0;1,1")

    def test_two_vertices_are_not_a_loop(self):
        with self.assertRaises(ValueError):
            sm.parse_lasso("1:0,0;1,1")

    def test_a_vertex_outside_the_picture_refuses(self):
        with self.assertRaises(ValueError):
            sm.parse_lasso("1:0,0;1.5,0;1,1")


class ApplyLassosTests(unittest.TestCase):
    def setUp(self):
        self.size = 64

    def loop(self, label, x0, y0, x1, y1):
        return {"label": label,
                "lasso": [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]}

    def test_an_include_unions(self):
        mask = np.zeros((self.size, self.size), dtype="float32")
        out = sm.apply_lassos(mask, [self.loop(1, 0.25, 0.25, 0.75, 0.75)])
        covered = float((out > 0.5).mean())
        self.assertGreater(covered, 0.2)
        self.assertLess(covered, 0.35)
        # The centre is claimed; the corner is not.
        self.assertGreater(out[self.size // 2, self.size // 2], 0.5)
        self.assertLess(out[1, 1], 0.5)

    def test_an_exclude_subtracts(self):
        mask = np.ones((self.size, self.size), dtype="float32")
        out = sm.apply_lassos(mask, [self.loop(0, 0.25, 0.25, 0.75, 0.75)])
        self.assertLess(out[self.size // 2, self.size // 2], 0.5)
        self.assertGreater(out[1, 1], 0.5)

    def test_draw_order_wins_where_loops_overlap(self):
        mask = np.zeros((self.size, self.size), dtype="float32")
        out = sm.apply_lassos(mask, [
            self.loop(1, 0.0, 0.0, 0.9, 0.9),
            self.loop(0, 0.4, 0.4, 0.6, 0.6),
        ])
        self.assertLess(out[self.size // 2, self.size // 2], 0.5,
                        "the later cut must win over the earlier add")
        self.assertGreater(out[self.size // 4, self.size // 4], 0.5)

    def test_no_loops_is_the_identity(self):
        mask = np.full((4, 4), 0.3, dtype="float32")
        self.assertIs(sm.apply_lassos(mask, []), mask)


class LassoOnlySelectTests(unittest.TestCase):
    """select() with loops and no clicks touches no model at all."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "cache"
        self.wallpaper = Path(self.tmp.name) / "wall.png"
        Image.new("RGB", (96, 64), (40, 80, 120)).save(self.wallpaper)

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_loop_becomes_a_candidate_with_its_prompt(self):
        entry = sm.parse_lasso(SQUARE)
        result = sm.select(self.root, str(self.wallpaper), "mobile-sam",
                           [], lassos=[entry])
        self.assertEqual(result["state"], "produced")
        mask_path = Path(result["mask"])
        self.assertTrue(mask_path.exists())
        # The stored prompt is the gesture, loops included.
        prompt = sm.read_prompt(mask_path)
        self.assertEqual(prompt, [entry])
        # And status hands it back the way it hands clicks back.
        status = sm.status(self.root, str(self.wallpaper))
        self.assertEqual(status["prompts"]["mobile-sam"], [entry])

    def test_a_cut_only_gesture_is_empty(self):
        result = sm.select(self.root, str(self.wallpaper), "mobile-sam",
                           [], lassos=[sm.parse_lasso("0:0.2,0.2;0.8,0.2;0.8,0.8")])
        self.assertEqual(result["state"], "empty")

    def test_no_gesture_at_all_clears(self):
        sm.select(self.root, str(self.wallpaper), "mobile-sam",
                  [], lassos=[sm.parse_lasso(SQUARE)])
        result = sm.select(self.root, str(self.wallpaper), "mobile-sam", [])
        self.assertEqual(result["state"], "cleared")
        self.assertEqual(sm.status(self.root, str(self.wallpaper))["candidates"], {})


if __name__ == "__main__":
    unittest.main()
