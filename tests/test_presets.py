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
    def test_wallpaper_engine_preset_transitions_before_runtime_swap(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config_dir = home / ".config/illogical-impulse"
            script_dir = home / ".config/quickshell/end4-pC/scripts"
            wallpaper_dir = script_dir / "wallpapers"
            colors_dir = script_dir / "colors"
            bin_dir = home / "bin"
            project_dir = home / "workshop/123"
            for path in (config_dir / "presets", wallpaper_dir, colors_dir, bin_dir, project_dir):
                path.mkdir(parents=True, exist_ok=True)
            event_log = home / "events.log"

            current = {
                "background": {"wallpaperPath": "/tmp/static-before.jpg"},
                "wallpaperSelector": {"wallpaperEngine": {
                    "activeProject": "", "activePath": "", "activeStill": "", "activePreview": "",
                }},
            }
            target = {
                **current,
                "wallpaperSelector": {"wallpaperEngine": {
                    "activeProject": "123", "activePath": str(project_dir),
                    "activeStill": "/tmp/123.png", "activePreview": "/tmp/123-preview.jpg",
                    "fps": 30, "scaling": "fill", "silent": True,
                }},
            }
            (config_dir / "config.json").write_text(json.dumps(current))
            (config_dir / "plugin-state.json").write_text(json.dumps({
                "version": 2, "desktopPositions": {}, "pluginOptions": {},
            }))
            (config_dir / "presets/live.json").write_text(json.dumps(target))

            helpers = {
                colors_dir / "switchwall.sh": 'printf "theme\\n" >> "$PRESET_EVENT_LOG"',
                wallpaper_dir / "wallpaper-engine.sh": 'printf "runtime %s\\n" "$1" >> "$PRESET_EVENT_LOG"',
                bin_dir / "qs": 'printf "transition %s\\n" "$*" >> "$PRESET_EVENT_LOG"',
            }
            for helper, body in helpers.items():
                helper.write_text(f"#!/usr/bin/env bash\n{body}\n")
                helper.chmod(0o755)

            env = dict(os.environ,
                HOME=str(home),
                PATH=f"{bin_dir}:{os.environ.get('PATH', '')}",
                PRESET_EVENT_LOG=str(event_log))
            subprocess.run(["bash", str(PRESETS), "--apply", "live"], env=env, check=True)

            events = event_log.read_text().splitlines()
            # The cross-fade is fired first (before the config write), then the
            # runtime is swapped, and colour theming runs last so it never stalls
            # the transition behind a multi-second matugen pass.
            self.assertTrue(events[0].startswith("transition -p "))
            self.assertEqual(events[1], "runtime apply")
            self.assertEqual(events[2], "theme")
            self.assertIn("/tmp/static-before.jpg", events[0])
            self.assertIn("/tmp/123-preview.jpg", events[0])

    def test_preset_transition_ipc_handler_exists(self):
        # presets.sh drives the cross-fade over IPC ("qs ipc call wallpaperEngine
        # transition ..."). Without this handler the call hits nothing and a
        # preset-applied wallpaper cuts straight to black. Guard both ends.
        engine = (ROOT / "services/WallpaperEngine.qml").read_text()
        presets = (ROOT / "scripts/presets.sh").read_text()
        self.assertIn('target: "wallpaperEngine"', engine)
        self.assertIn(
            "function transition(fromStill: string, fromPreview: string, toStill: string, toPreview: string)",
            engine,
        )
        self.assertIn("root.requestTransition(fromStill, fromPreview, toStill, toPreview)", engine)
        self.assertIn("ipc call wallpaperEngine transition", presets)

    def test_wallpaper_transition_paths_share_the_selected_animation(self):
        engine = (ROOT / "services/WallpaperEngine.qml").read_text()
        selector = (ROOT / "modules/ii/wallpaperSelector/WallpaperSelector.qml").read_text()
        background = (ROOT / "modules/ii/background/Background.qml").read_text()

        self.assertIn("root.requestTransition(fromStill, prevPreview", engine)
        self.assertIn('target: "wallpaperEngine"', selector)
        self.assertIn("WallpaperEngine.requestTransition", selector)
        self.assertIn("onWallpaperPathChanged:", background)
        self.assertIn("transitionAnim.restart()", background)
        self.assertIn("function onScreenLockedChanged()", background)
        self.assertIn("bgRoot.wallpaperEngineLockProgress = 1", background)
        self.assertIn("bgRoot.wallpaperEngineLockProgress = 0", background)

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
