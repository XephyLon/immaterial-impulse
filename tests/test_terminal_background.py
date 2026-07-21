#!/usr/bin/env python3
"""Regression tests for generated Kitty background-image settings."""

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/terminal/apply_terminal_background.py"
SPEC = importlib.util.spec_from_file_location("terminal_background", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class TerminalBackgroundTests(unittest.TestCase):
    def test_disabled_removes_managed_block_and_preserves_theme(self):
        existing = (
            "foreground #ffffff\n"
            f"{MODULE.START_MARKER}\nbackground_image /tmp/old.png\n"
            f"{MODULE.END_MARKER}\nbackground #000000\n"
        )
        rendered = MODULE.render(existing, {"enabled": False})
        self.assertEqual(rendered, "foreground #ffffff\nbackground #000000\n")

    def test_enabled_renders_validated_kitty_directives_once(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "pattern image.png"
            image.touch()
            settings = {
                "enabled": True,
                "imagePath": str(image),
                "layout": "mirror-tiled",
                "opacity": 0.18,
            }
            rendered = MODULE.render("foreground #ffffff\n", settings)
            rerendered = MODULE.render(rendered, settings)

        self.assertIn(f"background_image {image}", rerendered)
        self.assertIn("background_image_layout mirror-tiled", rerendered)
        self.assertIn("background_tint 0.82", rerendered)
        self.assertEqual(rerendered.count(MODULE.START_MARKER), 1)

    def test_opacity_is_clamped(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "pattern.png"
            image.touch()
            rendered = MODULE.render(
                "", {"enabled": True, "imagePath": str(image), "opacity": 2}
            )
        self.assertIn("background_tint 0.00", rendered)

    def test_relative_or_missing_image_is_rejected(self):
        for image_path in ("pattern.png", "/definitely/missing/pattern.png"):
            with self.subTest(image_path=image_path):
                with self.assertRaises(ValueError):
                    MODULE.render("", {"enabled": True, "imagePath": image_path})


if __name__ == "__main__":
    unittest.main()
