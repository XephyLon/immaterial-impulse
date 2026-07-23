#!/usr/bin/env python3
"""Tests for apply-icon-theme.sh: writes the right keys, rejects bad input."""
import configparser
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/icons/apply-icon-theme.sh"


class ApplyIconThemeTest(unittest.TestCase):
    def run_apply(self, theme_id, home):
        env = dict(os.environ)
        env["HOME"] = str(home)
        env["XDG_DATA_HOME"] = str(home / ".local/share")
        # No gsettings schema in CI: the script must tolerate its failure.
        return subprocess.run(
            ["bash", str(SCRIPT), theme_id],
            capture_output=True, text=True, env=env,
        )

    def make_theme(self, home, theme_id):
        d = home / ".local/share/icons" / theme_id
        d.mkdir(parents=True, exist_ok=True)
        (d / "index.theme").write_text("[Icon Theme]\nName=X\n", encoding="utf-8")

    def read_key(self, path, section, key):
        cp = configparser.ConfigParser(interpolation=None, strict=False)
        cp.optionxform = str
        cp.read(path, encoding="utf-8")
        return cp.get(section, key)

    def test_writes_all_targets(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            self.make_theme(home, "CoolIcons")
            res = self.run_apply("CoolIcons", home)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(
                self.read_key(home / ".config/gtk-3.0/settings.ini",
                              "Settings", "gtk-icon-theme-name"), "CoolIcons")
            self.assertEqual(
                self.read_key(home / ".config/gtk-4.0/settings.ini",
                              "Settings", "gtk-icon-theme-name"), "CoolIcons")
            self.assertEqual(
                self.read_key(home / ".config/kdeglobals", "Icons", "Theme"),
                "CoolIcons")

    def test_preserves_other_gtk_keys(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            self.make_theme(home, "CoolIcons")
            gtk3 = home / ".config/gtk-3.0/settings.ini"
            gtk3.parent.mkdir(parents=True, exist_ok=True)
            gtk3.write_text("[Settings]\ngtk-theme-name=adw-gtk3\n", encoding="utf-8")
            res = self.run_apply("CoolIcons", home)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(
                self.read_key(gtk3, "Settings", "gtk-theme-name"), "adw-gtk3")
            self.assertEqual(
                self.read_key(gtk3, "Settings", "gtk-icon-theme-name"), "CoolIcons")

    def test_rejects_injection_and_traversal(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            for bad in ["../evil", "x; rm -rf ~", "$(touch /tmp/pwned)", "a/b",
                        "clean\nx; rm -rf ~", ""]:
                res = self.run_apply(bad, home)
                self.assertNotEqual(res.returncode, 0)
            self.assertFalse((home / ".config/gtk-3.0/settings.ini").exists())

    def test_rejects_theme_not_on_disk(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            res = self.run_apply("NotInstalled", home)
            self.assertNotEqual(res.returncode, 0)

    def test_gtk_key_has_no_spaces_around_equals(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            self.make_theme(home, "CoolIcons")
            res = self.run_apply("CoolIcons", home)
            self.assertEqual(res.returncode, 0, res.stderr)
            text = (home / ".config/gtk-3.0/settings.ini").read_text(encoding="utf-8")
            self.assertIn("gtk-icon-theme-name=CoolIcons", text)
            self.assertNotIn("gtk-icon-theme-name =", text)


if __name__ == "__main__":
    unittest.main()
