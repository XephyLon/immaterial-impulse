#!/usr/bin/env python3
"""presets.sh --apply --only applies exactly the named sections.

Runs the real script in a temp HOME (the test_presets.py harness pattern:
copied script beside stub helpers, so $0-derived paths resolve there).
The fence assertion is the one that matters: `apps` survives untouched
unless named, whatever else is applied.
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRESETS = ROOT / "scripts/presets.sh"


def harness(directory):
    home = Path(directory)
    config_dir = home / ".config/immaterial-impulse"
    script_dir = home / ".config/quickshell/imi/scripts"
    (script_dir / "colors").mkdir(parents=True)
    config_dir.mkdir(parents=True)
    (script_dir / "colors/switchwall.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    (script_dir / "colors/switchwall.sh").chmod(0o755)
    script = script_dir / "presets.sh"
    shutil.copy(PRESETS, script)
    script.chmod(0o755)
    live = {
        "background": {"wallpaperPath": "/live.jpg"},
        "appearance": {"palette": {"type": "auto"}, "fonts": {"main": "LiveFont"},
                        "clock": {"style": "cookie"}},
        "apps": {"terminal": "live-terminal"},
        "bar": {"cornerStyle": 0},
        "sounds": {"enable": True},
        "wallpaperSelector": {"wallpaperEngine": {"activePath": ""}},
    }
    preset = {
        "_presetMeta": {"description": "d"},
        "_pluginState": {"version": 2, "pluginOptions": {"notes": {"blurEnabled": True}}},
        "background": {"wallpaperPath": "/preset.jpg"},
        "appearance": {"palette": {"type": "scheme-neutral"}, "fonts": {"main": "PresetFont"},
                        "clock": {"style": "digital"}},
        "apps": {"terminal": "evil --rm -rf"},
        "bar": {"cornerStyle": 3},
        "sounds": {"enable": False},
    }
    (config_dir / "config.json").write_text(json.dumps(live))
    (config_dir / "plugin-state.json").write_text(json.dumps({"version": 2, "pluginOptions": {}}))
    (config_dir / "presets").mkdir()
    (config_dir / "presets/mix.json").write_text(json.dumps(preset))
    return home, config_dir, script


def run(script, home, *args):
    return subprocess.run(["bash", str(script), *args],
                          env=dict(os.environ, HOME=str(home)),
                          capture_output=True, text=True)


class ApplyOnlyTests(unittest.TestCase):
    def test_only_applies_exactly_the_named_sections(self):
        with tempfile.TemporaryDirectory() as directory:
            home, config_dir, script = harness(directory)
            result = run(script, home, "--apply", "mix",
                         "--only", "background,appearance:palette")
            self.assertEqual(result.returncode, 0, result.stderr)
            config = json.loads((config_dir / "config.json").read_text())
            self.assertEqual(config["background"]["wallpaperPath"], "/preset.jpg")
            self.assertEqual(config["appearance"]["palette"]["type"], "scheme-neutral")
            # Unnamed sections keep the live values - the fence included.
            self.assertEqual(config["appearance"]["fonts"]["main"], "LiveFont")
            self.assertEqual(config["apps"]["terminal"], "live-terminal")
            self.assertEqual(config["bar"]["cornerStyle"], 0)
            # _pluginState was not named, so the plugin state is untouched.
            state = json.loads((config_dir / "plugin-state.json").read_text())
            self.assertEqual(state["pluginOptions"], {})

    def test_plugin_state_applies_only_when_named(self):
        with tempfile.TemporaryDirectory() as directory:
            home, config_dir, script = harness(directory)
            result = run(script, home, "--apply", "mix", "--only", "_pluginState")
            self.assertEqual(result.returncode, 0, result.stderr)
            state = json.loads((config_dir / "plugin-state.json").read_text())
            self.assertEqual(state["pluginOptions"]["notes"]["blurEnabled"], True)
            config = json.loads((config_dir / "config.json").read_text())
            self.assertEqual(config["background"]["wallpaperPath"], "/live.jpg")

    def test_commands_apply_when_deliberately_named(self):
        with tempfile.TemporaryDirectory() as directory:
            home, config_dir, script = harness(directory)
            run(script, home, "--apply", "mix", "--only", "apps")
            config = json.loads((config_dir / "config.json").read_text())
            self.assertEqual(config["apps"]["terminal"], "evil --rm -rf")

    def test_no_only_is_todays_full_apply(self):
        with tempfile.TemporaryDirectory() as directory:
            home, config_dir, script = harness(directory)
            run(script, home, "--apply", "mix")
            config = json.loads((config_dir / "config.json").read_text())
            self.assertEqual(config["apps"]["terminal"], "evil --rm -rf")
            self.assertEqual(config["bar"]["cornerStyle"], 3)
            state = json.loads((config_dir / "plugin-state.json").read_text())
            self.assertEqual(state["pluginOptions"]["notes"]["blurEnabled"], True)

    def test_unknown_spec_refuses_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            home, config_dir, script = harness(directory)
            before = (config_dir / "config.json").read_text()
            result = run(script, home, "--apply", "mix", "--only", "background,$(rm -rf /)")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((config_dir / "config.json").read_text(), before)


if __name__ == "__main__":
    unittest.main()
