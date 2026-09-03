#!/usr/bin/env python3
import json
import os
import shutil
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
            config_dir = home / ".config/immaterial-impulse"
            script_dir = home / ".config/quickshell/imi/scripts"
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

            # presets.sh self-locates from $0, so run a copy placed beside the
            # stub helpers rather than the real script in the source tree.
            presets = script_dir / "presets.sh"
            shutil.copy(PRESETS, presets)
            presets.chmod(0o755)

            env = dict(os.environ, HOME=str(home))
            subprocess.run(["bash", str(presets), "--save", "layout"], env=env, check=True)
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
            subprocess.run(["bash", str(presets), "--apply", "layout"], env=env, check=True)

            restored = json.loads(state_file.read_text())
            self.assertEqual(restored["desktopPositions"]["DP-1"]["weather"]["x"], 120)
            self.assertEqual(restored["pluginOptions"]["weather"], {
                "blurEnabled": True,
            })
            self.assertNotIn("_pluginState", json.loads(config_file.read_text()))

    def test_preset_persist_flag_shields_a_plugin_through_apply(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config_dir = home / ".config/immaterial-impulse"
            script_dir = home / ".config/quickshell/imi/scripts"
            (script_dir / "wallpapers").mkdir(parents=True)
            (script_dir / "colors").mkdir(parents=True)
            (config_dir / "presets").mkdir(parents=True)
            for helper in (script_dir / "wallpapers/wallpaper-engine.sh",
                           script_dir / "colors/switchwall.sh"):
                helper.write_text("#!/usr/bin/env bash\nexit 0\n")
                helper.chmod(0o755)
            presets = script_dir / "presets.sh"
            shutil.copy(PRESETS, presets)
            presets.chmod(0o755)
            env = dict(os.environ, HOME=str(home))

            config_file = config_dir / "config.json"
            state_file = config_dir / "plugin-state.json"
            config_file.write_text(json.dumps({
                "background": {"wallpaperPath": "/tmp/w.jpg"},
                "plugins": {"enabled": ["kept_plugin", "other_plugin"]},
            }))
            state_file.write_text(json.dumps({
                "version": 2,
                "desktopPositions": {"DP-1": {
                    "kept_plugin": {"x": 1, "y": 1, "placementStrategy": "free"},
                    "other_plugin": {"x": 2, "y": 2, "placementStrategy": "free"}}},
                "pluginOptions": {"kept_plugin": {"a": 1}, "other_plugin": {"b": 1}},
            }))
            subprocess.run(["bash", str(presets), "--save", "snap"], env=env, check=True)

            # The persist flag never enters the snapshot.
            preset = json.loads((config_dir / "presets/snap.json").read_text())
            self.assertNotIn("presetPersist", preset["_pluginState"])

            # Diverge live state: flag kept_plugin, change both plugins, disable it.
            config_file.write_text(json.dumps({
                "background": {"wallpaperPath": "/tmp/w.jpg"},
                "plugins": {"enabled": ["other_plugin"]},
            }))
            state_file.write_text(json.dumps({
                "version": 2,
                "desktopPositions": {"DP-1": {
                    "kept_plugin": {"x": 50, "y": 60, "placementStrategy": "free"},
                    "other_plugin": {"x": 70, "y": 80, "placementStrategy": "free"}}},
                "pluginOptions": {"kept_plugin": {"a": 9}, "other_plugin": {"b": 9}},
                "presetPersist": {"kept_plugin": True},
            }))
            subprocess.run(["bash", str(presets), "--apply", "snap"], env=env, check=True)

            state = json.loads(state_file.read_text())
            # Persisted plugin keeps live values; the other follows the preset.
            self.assertEqual(state["pluginOptions"]["kept_plugin"], {"a": 9})
            self.assertEqual(state["pluginOptions"]["other_plugin"], {"b": 1})
            self.assertEqual(state["desktopPositions"]["DP-1"]["kept_plugin"]["x"], 50)
            self.assertEqual(state["desktopPositions"]["DP-1"]["other_plugin"]["x"], 2)
            self.assertEqual(state["presetPersist"], {"kept_plugin": True})
            # Enabled membership follows live for the persisted plugin only.
            cfg = json.loads(config_file.read_text())
            self.assertNotIn("kept_plugin", cfg["plugins"]["enabled"])
            self.assertIn("other_plugin", cfg["plugins"]["enabled"])

    def test_save_prefers_authoritative_in_memory_plugin_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config_dir = home / ".config/immaterial-impulse"
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
        # Preset save/apply/remove moved from Profile.qml into the
        # services/Presets.qml singleton in the upstream "pf" refactor; the
        # snapshot-passing contract lives there now.
        presets_service = (ROOT / "services/Presets.qml").read_text()

        self.assertIn("function snapshot()", state)
        self.assertIn("function replaceSnapshot(text)", state)
        self.assertIn("writeTimer.stop()", state)
        self.assertIn('target: "pluginState"', state)
        self.assertIn("PluginState.snapshot()", presets_service)
        self.assertIn("ipc call pluginState replace", PRESETS.read_text())

    def test_position_only_preset_keeps_current_plugin_options(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config_dir = home / ".config/immaterial-impulse"
            script_dir = home / ".config/quickshell/imi/scripts"
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

            presets = script_dir / "presets.sh"
            shutil.copy(PRESETS, presets)
            presets.chmod(0o755)

            subprocess.run(["bash", str(presets), "--apply", "legacy"],
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


    def _sandbox(self, home, state):
        """A HOME with a plugin state, stub helpers and a copy of presets.sh."""
        config_dir = home / ".config/immaterial-impulse"
        script_dir = home / ".config/quickshell/imi/scripts"
        wallpaper_dir = script_dir / "wallpapers"
        colors_dir = script_dir / "colors"
        for d in (config_dir, wallpaper_dir, colors_dir):
            d.mkdir(parents=True, exist_ok=True)
        (config_dir / "config.json").write_text(json.dumps({
            "background": {"wallpaperPath": "/tmp/wallpaper.jpg"},
            "wallpaperSelector": {"wallpaperEngine": {"activePath": ""}},
        }))
        state_file = config_dir / "plugin-state.json"
        state_file.write_text(json.dumps(state))
        for helper in (wallpaper_dir / "wallpaper-engine.sh", colors_dir / "switchwall.sh"):
            helper.write_text("#!/usr/bin/env bash\nexit 0\n")
            helper.chmod(0o755)
        presets = script_dir / "presets.sh"
        shutil.copy(PRESETS, presets)
        presets.chmod(0o755)
        return config_dir, state_file, presets, dict(os.environ, HOME=str(home))

    def test_the_lock_layout_round_trips_and_an_old_preset_keeps_the_fork(self):
        """Two layouts, one store (spec §4.3 as amended 2026-08-18).

        A preset saved by this shell carries `lockPositions`; applying it
        restores the fork exactly. A preset from an OLDER shell has no such
        key, and applying it must leave the user's fork alone rather than
        wipe it - the same `has()` rule the desktop map already follows.
        """
        forked = {
            "version": 2,
            "desktopPositions": {"DP-1": {"clock": {"x": 100, "y": 200, "placementStrategy": "free"}}},
            "lockPositions": {"DP-1": {"clock": {"x": 900, "y": 900, "placementStrategy": "free"}}},
            "pluginOptions": {},
        }
        with tempfile.TemporaryDirectory() as directory:
            config_dir, state_file, presets, env = self._sandbox(Path(directory), forked)

            subprocess.run(["bash", str(presets), "--save", "forked"], env=env, check=True)
            preset = json.loads((config_dir / "presets/forked.json").read_text())
            self.assertEqual(preset["_pluginState"]["lockPositions"]["DP-1"]["clock"]["x"], 900,
                             "a saved preset must carry the lock layout")

            # Scribble on the fork, then apply the preset: the fork comes back.
            state_file.write_text(json.dumps({
                "version": 2,
                "desktopPositions": {"DP-1": {"clock": {"x": 1, "y": 1}}},
                "lockPositions": {"DP-1": {"clock": {"x": 2, "y": 2}}},
                "pluginOptions": {},
            }))
            subprocess.run(["bash", str(presets), "--apply", "forked"], env=env, check=True)
            restored = json.loads(state_file.read_text())
            self.assertEqual(restored["desktopPositions"]["DP-1"]["clock"]["x"], 100)
            self.assertEqual(restored["lockPositions"]["DP-1"]["clock"]["x"], 900)

            # An OLDER preset: same document with the lock key removed, as a
            # pre-fork shell would have written it.
            old = json.loads((config_dir / "presets/forked.json").read_text())
            del old["_pluginState"]["lockPositions"]
            (config_dir / "presets/older.json").write_text(json.dumps(old))
            state_file.write_text(json.dumps(forked))
            subprocess.run(["bash", str(presets), "--apply", "older"], env=env, check=True)
            after_old = json.loads(state_file.read_text())
            self.assertEqual(after_old["desktopPositions"]["DP-1"]["clock"]["x"], 100)
            self.assertEqual(after_old["lockPositions"]["DP-1"]["clock"]["x"], 900,
                             "a preset without lockPositions must not wipe the user's fork")

    def test_the_lock_widget_options_round_trip_and_an_old_preset_keeps_the_overlay(self):
        """A widget's settings fork per surface (2026-09-03): `lockOptions`
        rides beside `pluginOptions` under the same `has()` rule as
        `lockPositions`, and the presetPersist carve-out shields a plugin's
        lock settings the way it shields its desktop ones."""
        forked = {
            "version": 2,
            "desktopPositions": {},
            "lockPositions": {},
            "pluginOptions": {"monitor": {"vertical": False}, "clock": {"style": "pixel"}},
            "lockOptions": {"monitor": {"vertical": True}},
        }
        with tempfile.TemporaryDirectory() as directory:
            config_dir, state_file, presets, env = self._sandbox(Path(directory), forked)

            subprocess.run(["bash", str(presets), "--save", "forked"], env=env, check=True)
            preset = json.loads((config_dir / "presets/forked.json").read_text())
            self.assertTrue(preset["_pluginState"]["lockOptions"]["monitor"]["vertical"],
                            "a saved preset must carry the lock screen's widget options")

            state_file.write_text(json.dumps({
                "version": 2, "desktopPositions": {}, "lockPositions": {},
                "pluginOptions": {"monitor": {"vertical": True}},
                "lockOptions": {"monitor": {"vertical": False}, "clock": {"style": "digital"}},
            }))
            subprocess.run(["bash", str(presets), "--apply", "forked"], env=env, check=True)
            restored = json.loads(state_file.read_text())
            self.assertFalse(restored["pluginOptions"]["monitor"]["vertical"])
            self.assertTrue(restored["lockOptions"]["monitor"]["vertical"])
            self.assertNotIn("clock", restored["lockOptions"], "a preset's complete map replaces the current one")

            old = json.loads((config_dir / "presets/forked.json").read_text())
            del old["_pluginState"]["lockOptions"]
            (config_dir / "presets/older.json").write_text(json.dumps(old))
            state_file.write_text(json.dumps(forked))
            subprocess.run(["bash", str(presets), "--apply", "older"], env=env, check=True)
            after_old = json.loads(state_file.read_text())
            self.assertTrue(after_old["lockOptions"]["monitor"]["vertical"],
                            "a preset without lockOptions must not wipe the user's lock settings")

            # presetPersist shields the plugin's LOCK settings too.
            shielded = dict(forked, presetPersist={"monitor": True},
                            lockOptions={"monitor": {"vertical": False}, "other": {"a": 1}})
            state_file.write_text(json.dumps(shielded))
            subprocess.run(["bash", str(presets), "--apply", "forked"], env=env, check=True)
            after = json.loads(state_file.read_text())
            self.assertFalse(after["lockOptions"]["monitor"]["vertical"],
                             "a persisted plugin keeps its current lock settings through apply")
            self.assertNotIn("other", after["lockOptions"])

    def test_the_lock_widget_choice_round_trips_and_an_old_preset_keeps_the_fork(self):
        """The other half of the same fork: WHICH widgets the lock shows.

        `lockPresence` is null while the lock follows the desktop's enabled
        set and a map once the user has picked, so a preset has to carry both
        states - and a preset from a shell that predates the key must leave a
        user's picked set alone, the same `has()` rule the two layouts follow.
        """
        picked = {
            "version": 2,
            "desktopPositions": {},
            "lockPositions": {},
            "lockPresence": {"clock": True},
            "pluginOptions": {},
        }
        with tempfile.TemporaryDirectory() as directory:
            config_dir, state_file, presets, env = self._sandbox(Path(directory), picked)

            subprocess.run(["bash", str(presets), "--save", "picked"], env=env, check=True)
            preset = json.loads((config_dir / "presets/picked.json").read_text())
            self.assertEqual(preset["_pluginState"]["lockPresence"], {"clock": True},
                             "a saved preset must carry the lock's widget choice")

            # A different pick on disk, then apply: the preset's choice wins.
            state_file.write_text(json.dumps({
                "version": 2,
                "desktopPositions": {},
                "lockPositions": {},
                "lockPresence": {"weather": True},
                "pluginOptions": {},
            }))
            subprocess.run(["bash", str(presets), "--apply", "picked"], env=env, check=True)
            restored = json.loads(state_file.read_text())
            self.assertEqual(restored["lockPresence"], {"clock": True})

            # A preset saved while FOLLOWING carries a null, and applying it
            # must re-link rather than read as "says nothing" - a preset is the
            # layout, and following is one of its two states.
            following = json.loads((config_dir / "presets/picked.json").read_text())
            following["_pluginState"]["lockPresence"] = None
            (config_dir / "presets/following.json").write_text(json.dumps(following))
            subprocess.run(["bash", str(presets), "--apply", "following"], env=env, check=True)
            self.assertIsNone(json.loads(state_file.read_text())["lockPresence"],
                              "a preset saved while following must re-link the choice")

            # An OLDER preset: the key is absent, not null, and the user's
            # picked set survives.
            old = json.loads((config_dir / "presets/picked.json").read_text())
            del old["_pluginState"]["lockPresence"]
            (config_dir / "presets/older_presence.json").write_text(json.dumps(old))
            state_file.write_text(json.dumps(picked))
            subprocess.run(["bash", str(presets), "--apply", "older_presence"], env=env, check=True)
            self.assertEqual(json.loads(state_file.read_text())["lockPresence"],
                             {"clock": True},
                             "a preset without lockPresence must not wipe the user's choice")

    def test_saving_a_preset_does_not_publish_the_users_weather_key(self):
        """A preset is a document people share; config.json holds their key.

        Saved verbatim, posting a preset published the author's OpenWeatherMap
        key with it. Stripped on SAVE rather than on apply, because apply
        merges the preset over the recipient's config - a key left in the file
        would overwrite theirs too.
        """
        source = PRESETS.read_text()
        self.assertIn(".bar.weather.apiKey", source)
        save = source[source.index("del(._presetMeta, ._pluginState)"):]
        save = save[:save.index("$PRESETS_DIR")]
        self.assertIn('.bar.weather.apiKey = ""', save,
                      "the save filter must blank the key")

    def test_the_save_filter_survives_a_config_without_the_key(self):
        """`?` on the path, so a config that has never had a weather key is
        passed through rather than failing the save."""
        source = PRESETS.read_text()
        self.assertIn("if .bar.weather.apiKey? then", source)
        for document in ('{"bar":{"weather":{"apiKey":"SECRET"}}}',
                         '{"dock":{"edge":"left"}}'):
            result = subprocess.run(
                ["jq", 'if .bar.weather.apiKey? then .bar.weather.apiKey = "" else . end'],
                input=document, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            # The VALUE, not a substring of the output - "apiKey" itself
            # contains a K, which is how the first version of this assertion
            # failed against a filter that was working correctly.
            saved = json.loads(result.stdout)
            self.assertEqual(saved.get("bar", {}).get("weather", {}).get("apiKey", ""), "")


if __name__ == "__main__":
    unittest.main()
