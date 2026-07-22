#!/usr/bin/env python3
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRESETS = ROOT / "scripts/presets.sh"


class PresetTests(unittest.TestCase):
    def test_live_plugin_widgets_resync_when_persisted_state_changes(self):
        widget = (ROOT / "modules/common/plugins/PluginWidget.qml").read_text()

        self.assertIn("function applyPersistedPosition()", widget)
        self.assertIn("onCurrentConfigChanged: applyPersistedPosition()", widget)
        self.assertIn("Component.onCompleted: applyPersistedPosition()", widget)

    def test_complete_plugin_state_round_trips_between_presets(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config_dir = home / ".config/illogical-impulse"
            script_dir = home / ".config/quickshell/end4-pC/scripts"
            wallpaper_dir = script_dir / "wallpapers"
            colors_dir = script_dir / "colors"
            config_dir.mkdir(parents=True)
            wallpaper_dir.mkdir(parents=True)
            colors_dir.mkdir(parents=True)

            config_file = config_dir / "config.json"
            state_file = config_dir / "plugin-state.json"
            config_file.write_text(json.dumps({
                "background": {"wallpaperPath": "/tmp/wallpaper.jpg"},
                "wallpaperSelector": {"wallpaperEngine": {"activePath": ""}},
            }))
            state_file.write_text(json.dumps({
                "version": 2,
                "desktopPositions": {
                    "DP-1": {"weather": {"x": 120, "y": 240, "placementStrategy": "free"}}
                },
                "pluginOptions": {"weather": {"blurEnabled": True}},
            }))

            for helper in (wallpaper_dir / "wallpaper-engine.sh", colors_dir / "switchwall.sh"):
                helper.write_text("#!/usr/bin/env bash\nexit 0\n")
                helper.chmod(0o755)

            env = dict(os.environ, HOME=str(home))
            subprocess.run(["bash", str(PRESETS), "--save", "layout"], env=env, check=True)
            preset = json.loads((config_dir / "presets/layout.json").read_text())
            self.assertEqual(preset["_pluginState"]["desktopPositions"]["DP-1"]["weather"]["x"], 120)
            self.assertEqual(preset["_pluginState"]["pluginOptions"]["weather"], {
                "blurEnabled": True,
            })

            state_file.write_text(json.dumps({
                "version": 2,
                "desktopPositions": {"DP-1": {"weather": {"x": 999, "y": 999}}},
                "pluginOptions": {"weather": {"blurEnabled": False, "fontSize": 24}},
            }))
            subprocess.run(["bash", str(PRESETS), "--apply", "layout"], env=env, check=True)

            restored = json.loads(state_file.read_text())
            self.assertEqual(restored["desktopPositions"]["DP-1"]["weather"]["x"], 120)
            self.assertEqual(restored["pluginOptions"]["weather"], {
                "blurEnabled": True,
            })
            self.assertNotIn("_pluginState", json.loads(config_file.read_text()))

    def test_save_prefers_authoritative_in_memory_plugin_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config_dir = home / ".config/illogical-impulse"
            (config_dir / "presets").mkdir(parents=True)
            (config_dir / "config.json").write_text(json.dumps({
                "background": {"wallpaperPath": "/tmp/wallpaper.jpg"},
            }))
            # Simulate PluginState's 100 ms write debounce: disk is stale while
            # the Settings process already has the new option in memory.
            (config_dir / "plugin-state.json").write_text(json.dumps({
                "version": 2,
                "desktopPositions": {},
                "pluginOptions": {"weather": {"blurEnabled": False}},
            }))
            live_snapshot = json.dumps({
                "version": 2,
                "desktopPositions": {"DP-1": {"weather": {"x": 321, "y": 123}}},
                "pluginOptions": {"weather": {"blurEnabled": True}},
            })

            subprocess.run([
                "bash", str(PRESETS), "--save", "fresh", "", live_snapshot,
            ], env=os.environ | {"HOME": str(home)}, check=True)
            saved = json.loads((config_dir / "presets/fresh.json").read_text())

            self.assertTrue(saved["_pluginState"]["pluginOptions"]["weather"]["blurEnabled"])
            self.assertEqual(
                saved["_pluginState"]["desktopPositions"]["DP-1"]["weather"]["x"],
                321,
            )

    def test_plugin_state_exposes_atomic_snapshot_replace_contract(self):
        state = (ROOT / "modules/common/plugins/PluginState.qml").read_text()
        profile = (ROOT / "modules/ii/settings/pages/Profile.qml").read_text()

        self.assertIn("function snapshot()", state)
        self.assertIn("function replaceSnapshot(text)", state)
        self.assertIn("writeTimer.stop()", state)
        self.assertIn('target: "pluginState"', state)
        self.assertIn("PluginState.snapshot()", profile)
        self.assertIn("ipc call pluginState replace", PRESETS.read_text())

    def test_position_only_preset_keeps_current_plugin_options(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config_dir = home / ".config/illogical-impulse"
            script_dir = home / ".config/quickshell/end4-pC/scripts"
            (config_dir / "presets").mkdir(parents=True)
            (script_dir / "wallpapers").mkdir(parents=True)
            (script_dir / "colors").mkdir(parents=True)
            base = {
                "background": {"wallpaperPath": "/tmp/wallpaper.jpg"},
                "wallpaperSelector": {"wallpaperEngine": {"activePath": ""}},
            }
            (config_dir / "config.json").write_text(json.dumps(base))
            (config_dir / "plugin-state.json").write_text(json.dumps({
                "version": 2,
                "desktopPositions": {"DP-1": {"weather": {"x": 999, "y": 999}}},
                "pluginOptions": {"weather": {"blurEnabled": False}},
            }))
            (config_dir / "presets/legacy.json").write_text(json.dumps(base | {
                "_pluginState": {
                    "desktopPositions": {"DP-1": {"weather": {"x": 120, "y": 240}}},
                },
            }))
            for helper in (script_dir / "wallpapers/wallpaper-engine.sh", script_dir / "colors/switchwall.sh"):
                helper.write_text("#!/usr/bin/env bash\nexit 0\n")
                helper.chmod(0o755)

            subprocess.run(["bash", str(PRESETS), "--apply", "legacy"],
                           env=os.environ | {"HOME": str(home)}, check=True)
            restored = json.loads((config_dir / "plugin-state.json").read_text())

            self.assertEqual(restored["desktopPositions"]["DP-1"]["weather"]["x"], 120)
            self.assertEqual(restored["pluginOptions"]["weather"]["blurEnabled"], False)

    def test_preset_without_plugin_state_keeps_current_state(self):
        source = PRESETS.read_text()
        self.assertIn("preset_plugin_state=", source)
        self.assertIn('if [ -n "$preset_plugin_state" ]', source)

    def test_apply_does_not_replace_unchanged_watched_files(self):
        source = PRESETS.read_text()
        self.assertIn("replace_if_changed()", source)
        self.assertIn('cmp -s "$candidate" "$destination"', source)
        self.assertIn(
            'replace_if_changed "${PLUGIN_STATE_FILE}.tmp" "$PLUGIN_STATE_FILE"',
            source,
        )
        self.assertIn(
            'replace_if_changed "${CONFIG_FILE}.tmp" "$CONFIG_FILE"',
            source,
        )


if __name__ == "__main__":
    unittest.main()
