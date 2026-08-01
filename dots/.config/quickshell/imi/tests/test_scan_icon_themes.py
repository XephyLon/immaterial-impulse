#!/usr/bin/env python3
"""Tests for the icon-theme scanner: real themes kept, cursor-only excluded."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCANNER = Path(__file__).resolve().parents[1] / "scripts/icons/scan-icon-themes.py"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class ScanIconThemesTest(unittest.TestCase):
    def run_scanner(self, roots):
        result = subprocess.run(
            [sys.executable, str(SCANNER), *roots],
            capture_output=True, text=True, check=True,
        )
        return json.loads(result.stdout)

    def test_real_theme_kept_cursor_only_excluded(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            # A real app-icon theme with a sample icon on disk.
            write(root / "CoolIcons/index.theme",
                  "[Icon Theme]\nName=Cool Icons\nDirectories=48x48/apps\n\n"
                  "[48x48/apps]\nSize=48\nContext=Applications\nType=Fixed\n")
            write(root / "CoolIcons/48x48/apps/firefox.png", "x")
            # A cursor-only pack: must be excluded.
            write(root / "MyCursors/index.theme",
                  "[Icon Theme]\nName=My Cursors\nDirectories=cursors\n\n"
                  "[cursors]\nSize=24\nContext=Cursors\nType=Fixed\n")
            # hicolor: must be excluded (fallback base, not selectable).
            write(root / "hicolor/index.theme",
                  "[Icon Theme]\nName=Hicolor\nDirectories=48x48/apps\n")

            themes = self.run_scanner([str(root)])
            ids = {t["id"] for t in themes}
            self.assertIn("CoolIcons", ids)
            self.assertNotIn("MyCursors", ids)
            self.assertNotIn("hicolor", ids)

            cool = next(t for t in themes if t["id"] == "CoolIcons")
            self.assertEqual(cool["name"], "Cool Icons")
            self.assertTrue(cool["sampleIcons"])
            self.assertTrue(all(os.path.isabs(p) for p in cool["sampleIcons"]))
            self.assertTrue(all(os.path.exists(p) for p in cool["sampleIcons"]))

    def test_missing_root_is_ignored(self):
        themes = self.run_scanner(["/nonexistent/path/xyz"])
        self.assertEqual(themes, [])


if __name__ == "__main__":
    unittest.main()
