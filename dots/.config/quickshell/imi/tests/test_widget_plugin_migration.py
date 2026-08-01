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

    def test_migration_never_drops_existing_entries(self):
        """It appends to plugins.enabled; a user's third-party plugins must
        survive it untouched.
        """
        body = self.src[self.src.index("function migrateDesktopWidgetsToPlugins"):]
        self.assertNotRegex(body, r'setNestedValue\("plugins\.enabled",\s*\[\]')


if __name__ == "__main__":
    unittest.main()
