#!/usr/bin/env python3
"""Tests for the cursor-theme scanner: both formats found, icon packs excluded."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCANNER = Path(__file__).resolve().parents[1] / "scripts/cursor/scan-cursor-themes.py"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class ScanCursorThemesTest(unittest.TestCase):
    def run_scanner(self, roots):
        result = subprocess.run(
            [sys.executable, str(SCANNER), *roots],
            capture_output=True, text=True, check=True,
        )
        return json.loads(result.stdout)

    def test_xcursor_and_hyprcursor_found_icon_pack_excluded(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            # A classic XCursor theme: cursors/ payload + index.theme name.
            write(root / "Bibata-Modern-Classic/index.theme",
                  "[Icon Theme]\nName=Bibata Modern Classic\n")
            (root / "Bibata-Modern-Classic/cursors").mkdir(parents=True)
            # A hyprcursor-only theme: manifest, no cursors/ directory.
            write(root / "HyprBibata/manifest.hl",
                  "name = Hypr Bibata\ndescription = x\nversion = 1.0\n"
                  "cursors_directory = hyprcursors\n")
            # An app-icon theme with no cursors at all: must be excluded.
            write(root / "CoolIcons/index.theme",
                  "[Icon Theme]\nName=Cool Icons\nDirectories=48x48/apps\n")
            (root / "CoolIcons/48x48/apps").mkdir(parents=True)
            # The XCursor fallback stub: not a selectable theme.
            write(root / "default/index.theme",
                  "[Icon Theme]\nInherits=Bibata-Modern-Classic\n")
            (root / "default/cursors").mkdir(parents=True)

            themes = self.run_scanner([str(root)])
            by_id = {t["id"]: t for t in themes}
            self.assertIn("Bibata-Modern-Classic", by_id)
            self.assertIn("HyprBibata", by_id)
            self.assertNotIn("CoolIcons", by_id)
            self.assertNotIn("default", by_id)

            bibata = by_id["Bibata-Modern-Classic"]
            self.assertEqual(bibata["name"], "Bibata Modern Classic")
            self.assertTrue(bibata["xcursor"])
            self.assertFalse(bibata["hyprcursor"])

            hypr = by_id["HyprBibata"]
            self.assertEqual(hypr["name"], "Hypr Bibata")
            self.assertFalse(hypr["xcursor"])
            self.assertTrue(hypr["hyprcursor"])

    def test_falls_back_to_directory_name_without_metadata(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "BareTheme/cursors").mkdir(parents=True)
            themes = self.run_scanner([str(root)])
            self.assertEqual([t["name"] for t in themes], ["BareTheme"])

    def test_first_root_wins_on_duplicate_ids(self):
        with tempfile.TemporaryDirectory() as d:
            user_root = Path(d) / "user"
            system_root = Path(d) / "system"
            for root, name in ((user_root, "User Copy"), (system_root, "System Copy")):
                write(root / "Dupe/index.theme", f"[Icon Theme]\nName={name}\n")
                (root / "Dupe/cursors").mkdir(parents=True)
            themes = self.run_scanner([str(user_root), str(system_root)])
            self.assertEqual([t["name"] for t in themes], ["User Copy"])

    def test_missing_root_is_ignored(self):
        themes = self.run_scanner(["/nonexistent/path/xyz"])
        self.assertEqual(themes, [])


if __name__ == "__main__":
    unittest.main()
