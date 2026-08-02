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
