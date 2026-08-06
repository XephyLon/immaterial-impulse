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


class PreviewExtractionTests(unittest.TestCase):
    """The scanner turns a theme's own Xcursor pointer into a PNG preview.

    Qt cannot decode the Xcursor container, so the settings cards depend on
    this extraction; a silent regression degrades every card to the fallback
    icon with nothing logged. Driven through the real CLI with a synthetic
    Xcursor file built from the format spec (magic, TOC, ARGB32 frames), so
    no theme needs to be installed on the runner.
    """

    def run_scanner(self, roots, preview_dir=None):
        cmd = [sys.executable, str(SCANNER)]
        if preview_dir is not None:
            cmd += ["--preview-dir", str(preview_dir)]
        cmd += [str(r) for r in roots]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return json.loads(proc.stdout)

    def make_theme(self, root, frames=((8, 0xFF804020),), corrupt=False):
        import struct as s
        cursors = root / "MyTheme/cursors"
        cursors.mkdir(parents=True)
        if corrupt:
            (cursors / "left_ptr").write_bytes(b"not an xcursor at all")
            return
        blobs, toc = [], []
        pos = 16 + 12 * len(frames)
        for size, argb in frames:
            header = s.pack("<9I", 36, 0xFFFD0002, size, 1, size, size, 0, 0, 50)
            pixels = s.pack("<I", argb) * (size * size)
            toc.append(s.pack("<III", 0xFFFD0002, size, pos))
            blobs.append(header + pixels)
            pos += len(header) + len(pixels)
        data = (b"Xcur" + s.pack("<III", 16, 0x10000, len(frames))
                + b"".join(toc) + b"".join(blobs))
        (cursors / "left_ptr").write_bytes(data)

    def test_a_preview_png_is_extracted(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "icons"; prev = Path(td) / "prev"
            self.make_theme(root)
            themes = self.run_scanner([root], prev)
            self.assertEqual(len(themes), 1)
            path = themes[0]["previewPath"]
            self.assertTrue(path and Path(path).is_file(), "no preview written")
            with open(path, "rb") as f:
                self.assertEqual(f.read(8), b"\x89PNG\r\n\x1a\n", "not a PNG")

    def test_the_frame_nearest_64_is_chosen(self):
        # Themes ship many sizes; the preview must come from the crispest one
        # for the card, not whichever the TOC lists first.
        import struct as s
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "icons"; prev = Path(td) / "prev"
            self.make_theme(root, frames=((24, 0xFF000000), (64, 0xFFFFFFFF)))
            themes = self.run_scanner([root], prev)
            data = Path(themes[0]["previewPath"]).read_bytes()
            width = s.unpack(">I", data[16:20])[0]
            self.assertEqual(width, 64)

    def test_an_unparseable_pointer_degrades_to_no_preview(self):
        # Best-effort by contract: garbage in must mean an empty previewPath,
        # never a crash or a broken PNG.
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "icons"; prev = Path(td) / "prev"
            self.make_theme(root, corrupt=True)
            themes = self.run_scanner([root], prev)
            self.assertEqual(len(themes), 1)
            self.assertEqual(themes[0]["previewPath"], "")

    def test_no_preview_dir_means_no_extraction(self):
        # Older callers without --preview-dir must keep working.
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "icons"
            self.make_theme(root)
            themes = self.run_scanner([root])
            self.assertEqual(themes[0]["previewPath"], "")


if __name__ == "__main__":
    unittest.main()
