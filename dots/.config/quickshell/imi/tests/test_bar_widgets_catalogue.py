#!/usr/bin/env python3
"""The bar widget catalogue has one home, and the settings page reads it.

BarConfig.qml used to carry the whole catalogue - 21 hardcoded entries plus a
plugin derivation - while the bar itself had none. Edit Mode's stage 8 drawer
is a second consumer, and a second copy of a catalogue is the drift this suite
already reddens on elsewhere (`test_bar_widget_parity.py`: a capability added
to one copy and not the other, silently). So `BarWidgets.qml` is the one list,
and these checks are what stop the settings page growing its own back:

  - BarConfig must READ the singleton (`BarWidgets.available` /
    `BarWidgets.nameFor`) and must not re-derive the plugin half from
    `PluginManager.availablePlugins`;
  - BarConfig must not declare an inline catalogue row (`{ id: "...", ... }`)
    at all - one row is how the second copy starts;
  - every static row in BarWidgets keeps its `Translation.tr("...")` literal,
    because translations/tools/translation-manager.py extracts keys by
    scanning for exactly that call form and its `clean` command deletes keys
    nothing matches - a name held as a bare string would be stripped from
    every language file on the next clean;
  - a plugin's name must NOT go through tr(): a manifest's `name` is the
    author's string, not a translation key;
  - the singleton stays registered where its siblings are (both qmldirs -
    the live one, and the tests mirror spec §11.1 requires before any test
    can see it).

Nothing here reads raw file text: `_qml_source` blanks comments, for the
reason `test_background_fullscreen_suppression.py` records - a comment
mentioning the word being grepped for defeats a raw grep outright.
"""
import re
import unittest
from pathlib import Path

from test_background_fullscreen_suppression import _qml_source

ROOT = Path(__file__).resolve().parents[1]
BAR_CONFIG = ROOT / "modules/imi/settings/pages/BarConfig.qml"
BAR_WIDGETS = ROOT / "modules/common/plugins/BarWidgets.qml"
LIVE_QMLDIR = ROOT / "modules/common/plugins/qmldir"
MIRROR_QMLDIR = ROOT / "tests/imports/qs/modules/common/plugins/qmldir"

# A catalogue row: an object literal whose `id` is a bare widget id. The
# quoted token is letters only, so the singleton's own plugin map
# (`id: "plugin:" + plugin.id`) does not match - its literal holds a colon.
_CATALOGUE_ROW = re.compile(r'\{\s*id:\s*"([A-Za-z]+)"\s*,')


class BarWidgetsCatalogueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bar_config_src = _qml_source(BAR_CONFIG)
        cls.bar_config = cls.bar_config_src.code
        cls.bar_widgets_src = _qml_source(BAR_WIDGETS)
        cls.bar_widgets = cls.bar_widgets_src.code

    def test_the_files_parse(self):
        """Everything below is only as good as the brace matching."""
        self.assertEqual(self.bar_config_src.unclosed, 0,
                         "unbalanced braces in BarConfig.qml")
        self.assertEqual(self.bar_widgets_src.unclosed, 0,
                         "unbalanced braces in BarWidgets.qml")

    def test_bar_config_reads_the_singleton(self):
        self.assertIn("BarWidgets.available", self.bar_config,
                      "BarConfig must take its widget list from the "
                      "BarWidgets singleton, not a copy of its own.")
        self.assertIn("BarWidgets.nameFor", self.bar_config,
                      "BarConfig must resolve a widget id to its display "
                      "name through BarWidgets.nameFor.")

    def test_bar_config_declares_no_catalogue_of_its_own(self):
        rows = _CATALOGUE_ROW.findall(self.bar_config)
        self.assertEqual(rows, [],
                         f"BarConfig.qml declares catalogue rows of its own "
                         f"({rows}); the one list is BarWidgets.available.")

    def test_bar_config_does_not_rederive_the_plugin_half(self):
        self.assertNotIn("PluginManager.availablePlugins", self.bar_config,
                         "the plugin bar-widget derivation moved into "
                         "BarWidgets; a second one here is the copy that "
                         "rots.")

    def test_every_static_row_keeps_its_translation_literal(self):
        rows = _CATALOGUE_ROW.findall(self.bar_widgets)
        self.assertGreaterEqual(
            len(rows), 21,
            "the static catalogue shrank below the 21 widgets it was "
            "promoted with - or the row pattern stopped matching, which "
            "makes every check on it vacuous.")
        for match in _CATALOGUE_ROW.finditer(self.bar_widgets):
            row_end = self.bar_widgets.find("}", match.start())
            row = self.bar_widgets[match.start():row_end]
            self.assertIn(
                "Translation.tr(", row,
                f"static row '{match.group(1)}' does not spell its name as "
                f"a Translation.tr(\"...\") literal; the extraction tooling "
                f"only sees that form, and clean strips what it cannot see.")

    def test_a_plugin_name_is_not_a_translation_key(self):
        self.assertIn("name: plugin.name", self.bar_widgets,
                      "the plugin derivation must carry the manifest's own "
                      "name.")
        self.assertNotIn("Translation.tr(plugin.name", self.bar_widgets,
                         "a manifest's name is the author's string, not a "
                         "translation key.")

    def test_the_singleton_is_registered_where_its_siblings_are(self):
        pattern = re.compile(r"^singleton BarWidgets(?: 1\.0)? BarWidgets\.qml$",
                             re.MULTILINE)
        for qmldir in (LIVE_QMLDIR, MIRROR_QMLDIR):
            self.assertTrue(
                pattern.search(qmldir.read_text()),
                f"{qmldir} does not register BarWidgets; without the line "
                f"the singleton is invisible to whichever side lost it.")


if __name__ == "__main__":
    unittest.main()
