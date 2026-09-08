#!/usr/bin/env python3
"""The wallpaper's source colour is selectable, and both generators agree.

matugen picks the palette seed with --source-color-index 0 by default; its
--prefer criteria choose another candidate. The shell's own terminal
generator scores the image independently, so a --prefer run must hand it
matugen's chosen hex or the shell and the terminal disagree.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "modules/common/Config.qml"
SWITCHWALL = ROOT / "scripts/colors/switchwall.sh"
QUICK = ROOT / "modules/imi/settings/pages/QuickConfig.qml"
MODES = ("saturation", "less-saturation", "lightness", "darkness", "value")


class PaletteSourceMode(unittest.TestCase):
    def test_the_config_key_defaults_to_dominant(self):
        self.assertRegex(CONFIG.read_text(), r'property string sourceMode:\s*"dominant"')

    def test_switchwall_maps_every_mode_and_keeps_dominant_as_index_zero(self):
        src = SWITCHWALL.read_text()
        self.assertIn(".appearance.palette.sourceMode", src)
        for mode in MODES:
            self.assertIn(mode, src)
        self.assertIn('matugen_args=(--prefer "$source_mode")', src)
        self.assertIn("matugen_args=(--source-color-index 0)", src)

    def test_the_terminal_generator_follows_matugens_pick(self):
        src = SWITCHWALL.read_text()
        self.assertIn(".colors.source_color.dark.color", src)
        paths = re.findall(r'generate_colors_material_args=\(--path "(\$[a-z_]+)"\)\n\s*align_generator_with_matugen "\1"', src)
        self.assertEqual(len(paths), 2, paths)

    def test_settings_offers_it_and_rethemes(self):
        src = QUICK.read_text()
        block = src[src.index('text: Translation.tr("Source colour")'):]
        block = block[:block.index("options: [")]
        self.assertIn("Config.options.appearance.palette.sourceMode = value", block)
        self.assertIn("page.refreshTheme()", block)


if __name__ == "__main__":
    unittest.main()
