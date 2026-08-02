#!/usr/bin/env python3
"""Source contract for the desktop-widget -> plugin migration.

Existing installs carry background.widgets.*.enable; ported widgets read
plugins.enabled, which defaults to []. Without a migration every user loses
whatever they had on - including the clock, which defaults to on.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "modules/common/Config.qml"
BUNDLED = ROOT / "modules/common/plugins/bundled"
MANAGER = ROOT / "modules/common/plugins/PluginManager.qml"
STATE = ROOT / "modules/common/plugins/PluginState.qml"


class WidgetPluginMigration(unittest.TestCase):
    def setUp(self):
        self.src = CONFIG.read_text(encoding="utf-8")

    def test_migration_function_exists(self):
        self.assertIn("function migrateDesktopWidgetsToPlugins", self.src)

    def test_migration_has_a_marker_so_it_runs_once(self):
        """Without a marker the migration re-enables a widget every launch,
        so a user could never turn one off.
        """
        self.assertIn("migratedDesktopWidgets", self.src)

    def test_every_ported_widget_has_a_mapping(self):
        body = self.src[self.src.index("function migrateDesktopWidgetsToPlugins"):]
        mapping = self.src[self.src.index("desktopWidgetPluginIds"):]
        for key in ("clock", "weather", "calendar", "worldClock", "notes",
                    "userCard", "images", "visualizer", "customImage",
                    "media", "resources"):
            self.assertIn(key, mapping, f"no migration mapping for {key}")

    def test_deduplicated_widgets_map_to_the_plugin_that_already_ships(self):
        """resources/media/weather/notes are deleted rather than ported, so
        their state must land on the id of the plugin that already exists. A
        wrong id here silently drops the widget for anyone who had it on,
        because the marker records the migration as done either way.
        """
        mapping = self.src[self.src.index("desktopWidgetPluginIds"):]
        mapping = mapping[:mapping.index("})")]
        for key, plugin in (("resources", "nandoroid_system_monitor"),
                            ("media", "nandoroid_media"),
                            ("weather", "nandoroid_weather"),
                            ("notes", "notes")):
            self.assertRegex(mapping, rf'"{key}":\s*"{plugin}"',
                             f"{key} must migrate onto {plugin}")

    def test_migration_never_drops_existing_entries(self):
        """It appends to plugins.enabled; a user's third-party plugins must
        survive it untouched.
        """
        body = self.src[self.src.index("function migrateDesktopWidgetsToPlugins"):]
        self.assertNotRegex(body, r'setNestedValue\("plugins\.enabled",\s*\[\]')


class ClockSettingsMigrateTooNotJustTheToggle(unittest.TestCase):
    """A port carries the toggle, never the data - except for the clock.

    `desktopWidgetPluginIds` copies exactly one bit per widget: `enable`. For
    the clock that is not enough. It is the only built-in that ships on, and
    its four styles (cookie, digital, pixel, plus the quote overlay) look
    nothing like one another - so an upgrade that keeps `enable` and drops
    `style` repaints every existing desktop into the default cookie clock,
    with no setting the user can point at to explain it. Same for the digital
    font they picked and the quote they typed.

    These pin the second half of the migration: the map, the separate marker,
    and the handoff that actually gets the values into plugin-state.json.
    """

    def setUp(self):
        self.src = CONFIG.read_text(encoding="utf-8")
        self.state = STATE.read_text(encoding="utf-8")
        self.mapping = self.src[self.src.index("desktopClockOptionKeys"):]
        self.mapping = self.mapping[:self.mapping.index("})")]

    def legacy_clock_keys(self):
        """Every leaf under Config's own background.widgets.clock schema.

        Derived from the schema rather than hardcoded, so a clock setting
        added later fails this test instead of being silently dropped on the
        next person's upgrade.
        """
        src = self.src
        start = src.index("property JsonObject clock: JsonObject {",
                          src.index("property JsonObject widgets: JsonObject {"))
        indent = len(src[:start].split("\n")[-1])
        block, depth, prefix, keys = src[start:], 0, [], []
        for line in block.split("\n"):
            stripped = line.strip()
            nested = re.match(r"property JsonObject (\w+): JsonObject \{", stripped)
            leaf = re.match(r"property (?:bool|int|real|string) (\w+):", stripped)
            if nested:
                if depth:
                    prefix.append(nested.group(1))
                depth += 1
            elif leaf and depth:
                keys.append(".".join(prefix + [leaf.group(1)]))
            if stripped.startswith("}"):
                depth -= 1
                if prefix:
                    prefix.pop()
                if depth <= 0 and len(line) - len(line.lstrip()) <= indent:
                    break
        return keys

    # `enable` is the other half of the migration; the rest is per-monitor
    # layout the host owns through PluginState.position().
    HOST_OWNED = {"enable", "x", "y", "placementStrategy"}

    def test_every_persisted_clock_setting_has_a_plugin_option_key(self):
        missing = [key for key in self.legacy_clock_keys()
                   if key not in self.HOST_OWNED
                   and f'"{key}":' not in self.mapping]
        self.assertEqual(missing, [],
                         "these clock settings would be lost on upgrade: "
                         + ", ".join(missing))

    def test_the_style_is_carried(self):
        """The single highest-consequence value in the whole initiative."""
        self.assertRegex(self.mapping, r'"style":\s*"style"')
        self.assertRegex(self.mapping, r'"styleLocked":\s*"styleLocked"')

    def test_host_owned_keys_are_not_migrated_as_options(self):
        """x/y/placementStrategy are PluginState.position()'s, and `enable` is
        plugins.enabled. Copying them into pluginOptions would make a second,
        silently ignored copy of the widget's position.
        """
        for key in sorted(self.HOST_OWNED):
            self.assertNotIn(f'"{key}":', self.mapping,
                             f"{key} is host state, not a plugin option")

    def test_the_settings_migration_has_its_own_marker(self):
        """Reusing migratedDesktopWidgets would permanently exclude every
        install that already ran the enable-only migration - which is every
        install that has launched this branch once.
        """
        self.assertIn("migratedDesktopWidgetOptions", self.src)
        body = self.src[self.src.index(
            "function migrateDesktopWidgetOptionsToPlugins"):]
        body = body[:body.index("\n    }")]
        self.assertIn("migratedDesktopWidgetOptions", body)
        self.assertNotIn("migratedDesktopWidgets)", body)

    def test_plugin_state_drains_the_batch(self):
        """Config cannot write plugin-state.json, so the map alone migrates
        nothing. Without the drain the values are computed and thrown away.
        """
        self.assertIn("pendingPluginOptions", self.src)
        self.assertIn("pendingPluginOptions", self.state)
        self.assertIn("function drainPendingConfigOptions", self.state)

    def test_the_drain_never_overwrites_an_option_already_set(self):
        """It can run on any launch until it succeeds, so it must lose to a
        preference the user has since changed in the widget's own panel.
        """
        body = self.state[self.state.index("function drainPendingConfigOptions"):]
        body = body[:body.index("\n    }")]
        self.assertIn("!== undefined", body,
                      "the drain must skip keys the plugin already has")

    def test_the_marker_is_written_after_the_values(self):
        """Marker first would record a migration that a crash could lose."""
        body = self.state[self.state.index("function drainPendingConfigOptions"):]
        body = body[:body.index("\n    }")]
        self.assertLess(body.index("root.state = nextState"),
                        body.index("migratedDesktopWidgetOptions = true"))


class BundledPluginsAreRegistered(unittest.TestCase):
    """Bundled plugins are not auto-discovered.

    PluginManager needs a FileView per bundled package AND that FileView's id
    inside rebuildFromLoadedFiles()'s array. Miss either half and the plugin
    silently never exists - which is exactly how a ported desktop widget
    disappears without a single error in the log.
    """

    def setUp(self):
        self.src = MANAGER.read_text(encoding="utf-8")
        self.file_views = dict(re.findall(
            r"id:\s*(\w+)\s*\n\s*property string pluginBase:"
            r' Quickshell\.shellPath\("modules/common/plugins/bundled/([^"]+)"\)',
            self.src))
        body = self.src[self.src.index("function rebuildFromLoadedFiles"):]
        self.rebuild_list = body[body.index("["):body.index("].forEach")]

    def test_every_bundled_package_has_a_file_view(self):
        for directory in sorted(BUNDLED.iterdir()):
            if not (directory / "manifest.json").exists():
                continue
            self.assertIn(directory.name, self.file_views.values(),
                          f"{directory.name} has no FileView in PluginManager")

    def test_every_file_view_is_read_by_the_rebuild(self):
        for view_id, package in self.file_views.items():
            self.assertIn(view_id, self.rebuild_list,
                          f"{package}'s FileView is never read by "
                          "rebuildFromLoadedFiles")


if __name__ == "__main__":
    unittest.main()
