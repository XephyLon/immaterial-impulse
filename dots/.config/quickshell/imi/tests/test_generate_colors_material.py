#!/usr/bin/env python3
"""Golden pins for scripts/colors/generate_colors_material.py basics.

MaterialThemeLoader.applyGeneratedColors parses stdout lines of the form
`$name: value;` and applyColors maps each name to an m3<CamelCase> role on
Appearance.m3colors, so the emitted key set and line format are a contract
with the shell. Also pins that scheme choice actually steers saturation
(monochrome -> gray primary, content -> saturated primary on a saturated
image), which is what the whole scheme plumbing exists for.

Needs the color venv (materialyoucolor + PIL); without it the behavioral
cases SKIP and the suite exits 0.
"""
import importlib.util
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts/colors/generate_colors_material.py"
FIXTURE = ROOT / "tests/fixtures/colorful_64.png"

# The QML parser in MaterialThemeLoader.applyGeneratedColors:
#   /^\$([A-Za-z0-9_]+):\s*([^;]+);/
QML_LINE_RE = re.compile(r"^\$([A-Za-z0-9_]+):\s*([^;]+);")

# Roles the shell reads off Appearance.m3colors (m3primary, m3surface, ...);
# snake_case internal palette keys are ignored by the loader, so what matters
# is that these public ones exist.
REQUIRED_KEYS = {
    "darkmode",
    "primary",
    "onPrimary",
    "primaryContainer",
    "background",
    "surface",
    "onSurface",
    "surfaceContainer",
    "surfaceContainerLow",
    "outline",
    "error",
    "success",
    "onSuccess",
}

def _has(module):
    try:
        return importlib.util.find_spec(module) is not None
    except (ImportError, ValueError):
        return False

HAVE_DEPS = _has("materialyoucolor") and _has("PIL")
SKIP_MSG = "SKIP: materialyoucolor/PIL not importable (color venv not active)"

if not HAVE_DEPS:
    print(SKIP_MSG, flush=True)


def generate(args):
    result = subprocess.run(
        [sys.executable, str(GENERATOR), *args],
        capture_output=True, text=True, timeout=120,
    )
    return result


def parse_colors(stdout):
    colors = {}
    for line in stdout.splitlines():
        match = QML_LINE_RE.match(line)
        if match:
            colors[match.group(1)] = match.group(2).strip()
    return colors


def hex_spread(value):
    """max(channel) - min(channel): 0 for pure gray, large when saturated."""
    r, g, b = (int(value[i:i + 2], 16) for i in (1, 3, 5))
    return max(r, g, b) - min(r, g, b)


@unittest.skipUnless(HAVE_DEPS, SKIP_MSG)
class GeneratorGoldenBasics(unittest.TestCase):
    def setUp(self):
        self.assertTrue(FIXTURE.is_file(), f"missing fixture {FIXTURE}")

    def run_and_parse(self, mode, scheme):
        result = generate(["--path", str(FIXTURE), "--mode", mode,
                           "--scheme", scheme])
        self.assertEqual(result.returncode, 0, result.stderr)
        colors = parse_colors(result.stdout)
        self.assertTrue(colors, "no `$name: value;` lines the shell can parse")
        return colors

    def test_dark_output_has_required_shell_keys(self):
        colors = self.run_and_parse("dark", "scheme-content")
        missing = REQUIRED_KEYS - colors.keys()
        self.assertFalse(missing, f"missing keys the shell consumes: {missing}")
        self.assertEqual(colors["darkmode"], "True")

    def test_light_output_has_required_shell_keys(self):
        colors = self.run_and_parse("light", "scheme-content")
        missing = REQUIRED_KEYS - colors.keys()
        self.assertFalse(missing, f"missing keys the shell consumes: {missing}")
        self.assertEqual(colors["darkmode"], "False")

    def test_color_values_are_hex_the_shell_understands(self):
        colors = self.run_and_parse("dark", "scheme-content")
        for key in REQUIRED_KEYS - {"darkmode"}:
            self.assertRegex(colors[key], r"^#[0-9A-Fa-f]{6}$",
                             f"${key} is not a #RRGGBB hex color")

    def test_monochrome_scheme_yields_grayish_primary(self):
        colors = self.run_and_parse("dark", "scheme-monochrome")
        spread = hex_spread(colors["primary"])
        self.assertLessEqual(
            spread, 8,
            f"scheme-monochrome primary {colors['primary']} is saturated "
            f"(channel spread {spread})")

    def test_content_scheme_yields_saturated_primary_on_saturated_image(self):
        colors = self.run_and_parse("dark", "scheme-content")
        spread = hex_spread(colors["primary"])
        self.assertGreaterEqual(
            spread, 30,
            f"scheme-content primary {colors['primary']} lost the fixture's "
            f"saturation (channel spread {spread})")

    def test_same_invocation_is_deterministic(self):
        args = ["--path", str(FIXTURE), "--mode", "dark",
                "--scheme", "scheme-content"]
        first = generate(args)
        second = generate(args)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout,
                         "generator output is not deterministic; parity "
                         "guarantees are meaningless if it drifts run to run")


if __name__ == "__main__":
    unittest.main()
