#!/usr/bin/env python3
import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "scripts/colors/install_matugen_app_themes.sh"
APPLICATOR = ROOT / "scripts/colors/apply_matugen_app_themes.py"


def load_applicator():
    spec = importlib.util.spec_from_file_location("apply_matugen_app_themes", APPLICATOR)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


class MatugenApplicationThemeTests(unittest.TestCase):
    def test_installer_registers_templates_idempotently(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config_home = root / "config"
            state_home = root / "state"
            matugen = config_home / "matugen/config.toml"
            matugen.parent.mkdir(parents=True)
            matugen.write_text("[config]\nversion_check = false\n")
            env = os.environ | {
                "XDG_CONFIG_HOME": str(config_home),
                "XDG_STATE_HOME": str(state_home),
            }

            subprocess.run([str(INSTALLER)], check=True, env=env)
            subprocess.run([str(INSTALLER)], check=True, env=env)
            content = matugen.read_text()

            self.assertEqual(content.count("[templates.end4_cava]"), 1)
            self.assertEqual(content.count("[templates.end4_btop]"), 1)
            self.assertEqual(content.count("[templates.end4_tmux]"), 1)
            self.assertIn("[config]\nversion_check = false", content)

    def test_installer_bootstraps_an_empty_matugen_config(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = os.environ | {
                "XDG_CONFIG_HOME": str(root / "config"),
                "XDG_STATE_HOME": str(root / "state"),
            }

            subprocess.run([str(INSTALLER)], check=True, env=env)
            content = (root / "config/matugen/config.toml").read_text()

            self.assertTrue(content.startswith("[config]\nversion_check = false"))

    def test_applicator_preserves_non_color_settings(self):
        app = load_applicator()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app.CONFIG = root / "config"
            app.STATE = root / "state"
            app.GENERATED = app.STATE / "quickshell/user/generated/apps"
            app.GENERATED.mkdir(parents=True)
            (app.GENERATED / "cava.ini").write_text(
                "[color]\nforeground = '#abcdef'\n"
            )
            cava = app.CONFIG / "cava/config"
            cava.parent.mkdir(parents=True)
            cava.write_text(
                "[general]\nframerate = 144\n\n[color]\nforeground = '#000000'\n\n"
                "[smoothing]\nnoise_reduction = 42\n"
            )

            with mock.patch.object(app.subprocess, "run"):
                app.apply_cava()
            updated = cava.read_text()

            self.assertIn("framerate = 144", updated)
            self.assertIn("noise_reduction = 42", updated)
            self.assertIn("foreground = '#abcdef'", updated)
            self.assertNotIn("foreground = '#000000'", updated)

    def test_btop_and_tmux_use_generated_theme_files(self):
        app = load_applicator()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app.CONFIG = root / "config"
            app.STATE = root / "state"
            app.GENERATED = app.STATE / "quickshell/user/generated/apps"
            app.GENERATED.mkdir(parents=True)
            (app.GENERATED / "btop.theme").write_text("theme[main_fg]=\"#abcdef\"\n")
            (app.GENERATED / "tmux.conf").write_text("set -g status-style 'fg=#abcdef'\n")
            btop = app.CONFIG / "btop/btop.conf"
            tmux = app.CONFIG / "tmux/tmux.conf"
            btop.parent.mkdir(parents=True)
            tmux.parent.mkdir(parents=True)
            btop.write_text('update_ms = 500\ncolor_theme = "Default"\n')
            tmux.write_text("set -g mouse on\n")

            with mock.patch.object(app.subprocess, "run"):
                app.apply_btop()
                app.apply_tmux()

            self.assertIn('color_theme = "matugen"', btop.read_text())
            self.assertIn("update_ms = 500", btop.read_text())
            self.assertIn("source-file -q", tmux.read_text())
            self.assertIn("set -g mouse on", tmux.read_text())
            self.assertTrue((app.CONFIG / "btop/themes/matugen.theme").is_file())
            self.assertTrue((app.CONFIG / "tmux/matugen.conf").is_file())

    def test_switcher_installs_renders_and_applies_themes_in_order(self):
        switcher = (ROOT / "scripts/colors/switchwall.sh").read_text()
        install = switcher.index('"$SCRIPT_DIR/install_matugen_app_themes.sh"')
        render = switcher.index('matugen "${matugen_args[@]}"')
        apply = switcher.index('python3 "$SCRIPT_DIR/apply_matugen_app_themes.py"')
        self.assertLess(install, render)
        self.assertLess(render, apply)


if __name__ == "__main__":
    unittest.main()
