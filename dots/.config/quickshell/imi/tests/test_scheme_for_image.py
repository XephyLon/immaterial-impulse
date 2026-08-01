#!/usr/bin/env python3
"""Behavioral pins for scripts/colors/scheme_for_image.py.

This is the detector both palette paths share for --scheme auto (desktop via
switchwall.sh, lock via generate-colors-venv.sh), so its output vocabulary and
failure behavior are load-bearing: a scheme name outside the generator's
vocabulary or a nonzero-exit path that still prints garbage would silently
skew one palette but not the other.

Needs cv2 + numpy (shipped in the color venv); without them the behavioral
cases SKIP and the suite exits 0. The static vocabulary pin always runs.
"""
import importlib.util
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/colors/scheme_for_image.py"
COLORFUL = ROOT / "tests/fixtures/colorful_64.png"
LOW_CHROMA = ROOT / "tests/fixtures/low_chroma_64.png"

# The generator's full scheme vocabulary; anything the detector prints must be
# a member, or generate_colors_material.py falls back silently.
ALLOWED_SCHEMES = {
    "scheme-content",
    "scheme-expressive",
    "scheme-fidelity",
    "scheme-fruit-salad",
    "scheme-monochrome",
    "scheme-neutral",
    "scheme-rainbow",
    "scheme-tonal-spot",
    "scheme-vibrant",
}

def _has(module):
    try:
        return importlib.util.find_spec(module) is not None
    except (ImportError, ValueError):
        return False

HAVE_DEPS = _has("cv2") and _has("numpy")
SKIP_MSG = "SKIP: cv2/numpy not importable (color venv not active)"

if not HAVE_DEPS:
    print(f"{SKIP_MSG} - running static contracts only", flush=True)


def run_detector(args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *[str(a) for a in args]],
        capture_output=True, text=True, timeout=120,
    )


class StaticContracts(unittest.TestCase):
    def test_script_only_emits_known_scheme_names(self):
        text = SCRIPT.read_text()
        emitted = set()
        for match in re.finditer(r'"(scheme-[a-z-]+)"', text):
            emitted.add(match.group(1))
        self.assertTrue(emitted, "no scheme literals found in detector")
        self.assertLessEqual(
            emitted, ALLOWED_SCHEMES,
            "detector emits a scheme name the generator does not understand")


@unittest.skipUnless(HAVE_DEPS, SKIP_MSG)
class DetectorBehavior(unittest.TestCase):
    def test_colorful_image_detects_exactly_one_known_scheme(self):
        result = run_detector([COLORFUL])
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 1,
                         f"expected exactly one line, got {lines!r}")
        self.assertIn(lines[0], ALLOWED_SCHEMES)
        # Two flat saturated regions score far above the colorfulness
        # threshold, so detection must not degrade to neutral.
        self.assertEqual(lines[0], "scheme-tonal-spot")

    def test_low_chroma_image_detects_neutral(self):
        result = run_detector([LOW_CHROMA])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "scheme-neutral")

    def test_missing_file_exits_nonzero_with_safe_fallback(self):
        result = run_detector(["/nonexistent/no-such-image.png"])
        self.assertNotEqual(result.returncode, 0,
                            "unreadable image must exit nonzero")
        # Pinned behavior: it still prints the safe default on stdout, which
        # is what the wrapper's `2>/dev/null | tr -d '\n'` capture relies on.
        self.assertEqual(result.stdout.strip(), "scheme-tonal-spot")

    def test_no_arguments_exits_nonzero_with_safe_fallback(self):
        result = run_detector([])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "scheme-tonal-spot")

    def test_colorfulness_mode_prints_a_number(self):
        result = run_detector(["--colorfulness", COLORFUL])
        self.assertEqual(result.returncode, 0, result.stderr)
        float(result.stdout.strip())  # raises (fails the test) if not numeric


if __name__ == "__main__":
    unittest.main()
