#!/usr/bin/env python3
"""Tests for the cursor apply path.

Two scripts share it: scripts/cursor/apply-cursor-theme.sh (the settings page's
apply: hyprctl setcursor + GTK inis + the XCursor default stub) and the hypr
dots' apply_saved_cursor.sh (startup: read the shell config, fall back to the
formerly hardcoded values). Both run against a fake hyprctl that records its
argv, so no compositor is touched.
"""
import configparser
import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APPLY = ROOT / "scripts/cursor/apply-cursor-theme.sh"
STARTUP = ROOT.parents[1] / "hypr/hyprland/scripts/apply_saved_cursor.sh"
EXECS = ROOT.parents[1] / "hypr/hyprland/execs.lua"


def fake_hyprctl(bin_dir: Path, log: Path, exit_code: int = 0) -> None:
    bin_dir.mkdir(parents=True, exist_ok=True)
    hyprctl = bin_dir / "hyprctl"
    hyprctl.write_text(
        f'#!/usr/bin/env bash\nprintf \'%s\\n\' "$*" >> "{log}"\nexit {exit_code}\n',
        encoding="utf-8")
    hyprctl.chmod(hyprctl.stat().st_mode | stat.S_IXUSR)


def run_script(script: Path, args, home: Path, bin_dir: Path):
    env = dict(os.environ)
    env["HOME"] = str(home)
    env["XDG_DATA_HOME"] = str(home / ".local/share")
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    return subprocess.run(
        ["bash", str(script), *args], capture_output=True, text=True, env=env)


def read_key(path, section, key):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    cp.read(path, encoding="utf-8")
    return cp.get(section, key)


class ApplyCursorThemeTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.home = Path(self._tmp.name)
        self.bin = self.home / "fakebin"
        self.log = self.home / "hyprctl.log"
        fake_hyprctl(self.bin, self.log)
        self.addCleanup(self._tmp.cleanup)

    def make_theme(self, theme_id, kind="xcursor"):
        d = self.home / ".local/share/icons" / theme_id
        if kind == "xcursor":
            (d / "cursors").mkdir(parents=True, exist_ok=True)
        else:
            d.mkdir(parents=True, exist_ok=True)
            (d / "manifest.hl").write_text("name = X\n", encoding="utf-8")

    def apply(self, theme, size):
        return run_script(APPLY, [theme, size], self.home, self.bin)

    def test_applies_to_all_targets(self):
        self.make_theme("CoolCursors")
        res = self.apply("CoolCursors", "32")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.log.read_text(encoding="utf-8"),
                         "setcursor CoolCursors 32\n")
        for gtk in ("gtk-3.0", "gtk-4.0"):
            ini = self.home / f".config/{gtk}/settings.ini"
            self.assertEqual(read_key(ini, "Settings", "gtk-cursor-theme-name"),
                             "CoolCursors")
            self.assertEqual(read_key(ini, "Settings", "gtk-cursor-theme-size"),
                             "32")
        self.assertEqual(
            read_key(self.home / ".icons/default/index.theme",
                     "Icon Theme", "Inherits"), "CoolCursors")

    def test_hyprcursor_only_theme_is_accepted(self):
        self.make_theme("HyprOnly", kind="hyprcursor")
        res = self.apply("HyprOnly", "24")
        self.assertEqual(res.returncode, 0, res.stderr)

    def test_preserves_other_gtk_keys(self):
        self.make_theme("CoolCursors")
        gtk3 = self.home / ".config/gtk-3.0/settings.ini"
        gtk3.parent.mkdir(parents=True, exist_ok=True)
        gtk3.write_text("[Settings]\ngtk-theme-name=adw-gtk3\n", encoding="utf-8")
        res = self.apply("CoolCursors", "24")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(read_key(gtk3, "Settings", "gtk-theme-name"), "adw-gtk3")

    def test_rejects_injection_and_traversal(self):
        for bad in ["../evil", "x; rm -rf ~", "$(touch /tmp/pwned)", "a/b", ""]:
            res = self.apply(bad, "24")
            self.assertNotEqual(res.returncode, 0, bad)
        self.assertFalse(self.log.exists())

    def test_rejects_bad_sizes(self):
        self.make_theme("CoolCursors")
        for bad in ["", "abc", "-5", "0", "7", "999", "24; rm -rf ~"]:
            res = self.apply("CoolCursors", bad)
            self.assertNotEqual(res.returncode, 0, bad)
        self.assertFalse(self.log.exists())

    def test_rejects_theme_without_cursors(self):
        d = self.home / ".local/share/icons/IconsOnly/48x48/apps"
        d.mkdir(parents=True)
        res = self.apply("IconsOnly", "24")
        self.assertNotEqual(res.returncode, 0)

    def test_hyprctl_failure_fails_before_writing_configs(self):
        self.make_theme("CoolCursors")
        fake_hyprctl(self.bin, self.log, exit_code=1)
        res = self.apply("CoolCursors", "24")
        self.assertNotEqual(res.returncode, 0)
        self.assertFalse((self.home / ".config/gtk-3.0/settings.ini").exists())


class ApplySavedCursorStartupTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.home = Path(self._tmp.name)
        self.bin = self.home / "fakebin"
        self.log = self.home / "hyprctl.log"
        fake_hyprctl(self.bin, self.log)
        self.addCleanup(self._tmp.cleanup)

    def run_startup(self):
        return run_script(STARTUP, [], self.home, self.bin)

    def write_config(self, cursor, directory="immaterial-impulse"):
        cfg = self.home / f".config/{directory}/config.json"
        cfg.parent.mkdir(parents=True, exist_ok=True)
        cfg.write_text(json.dumps({"hyprland": {"cursor": cursor}}),
                       encoding="utf-8")

    def test_uses_configured_theme_and_size(self):
        self.write_config({"theme": "Catppuccin-Mocha", "size": 32})
        res = self.run_startup()
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.log.read_text(encoding="utf-8"),
                         "setcursor Catppuccin-Mocha 32\n")

    def test_falls_back_to_former_hardcoded_values_without_config(self):
        res = self.run_startup()
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.log.read_text(encoding="utf-8"),
                         "setcursor Bibata-Modern-Classic 24\n")

    def test_reads_the_legacy_config_directory_before_migration(self):
        self.write_config({"theme": "LegacyTheme", "size": 28},
                          directory="illogical-impulse")
        res = self.run_startup()
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.log.read_text(encoding="utf-8"),
                         "setcursor LegacyTheme 28\n")

    def test_malformed_config_and_missing_keys_fall_back(self):
        cfg = self.home / ".config/immaterial-impulse/config.json"
        cfg.parent.mkdir(parents=True, exist_ok=True)
        for content in ["not json {", json.dumps({"hyprland": {}}),
                        json.dumps({"hyprland": {"cursor": {"size": "huh"}}})]:
            cfg.write_text(content, encoding="utf-8")
            self.log.unlink(missing_ok=True)
            res = self.run_startup()
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(self.log.read_text(encoding="utf-8"),
                             "setcursor Bibata-Modern-Classic 24\n",
                             content)

    def test_execs_lua_calls_the_script_not_a_hardcoded_literal(self):
        source = EXECS.read_text(encoding="utf-8")
        self.assertIn("apply_saved_cursor.sh", source)
        self.assertNotIn("setcursor Bibata", source)


if __name__ == "__main__":
    unittest.main()
