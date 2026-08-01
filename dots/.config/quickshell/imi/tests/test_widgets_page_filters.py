#!/usr/bin/env python3
"""Source contract for the Widgets page filter UI.

The QML suite instantiates pure-logic singletons and never builds widgets, so
these are greppable pins on the parts of the Widgets page IA that fail silently
when they regress.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHIP = ROOT / "modules/common/widgets/FilterChip.qml"
STORE = ROOT / "modules/imi/settings/pages/PluginStorePage.qml"


class FilterChipIsShared(unittest.TestCase):
    def test_chip_is_a_shared_widget_file(self):
        self.assertTrue(CHIP.exists(),
                        "FilterChip must live in modules/common/widgets")

    def test_chip_is_a_ripple_button(self):
        src = CHIP.read_text(encoding="utf-8")
        self.assertRegex(src, r"(?m)^RippleButton\s*\{")

    def test_chip_exposes_label_and_icon(self):
        src = CHIP.read_text(encoding="utf-8")
        self.assertIn("property string label", src)
        self.assertIn("property string chipIcon", src)

    def test_store_no_longer_declares_a_local_chip(self):
        """A page-local `component FilterChip` is how the chip got trapped in a
        gated-off page in the first place. If it comes back, the two filter
        surfaces can drift apart again.
        """
        src = STORE.read_text(encoding="utf-8")
        self.assertNotRegex(src, r"component\s+FilterChip\s*:",
                            "PluginStorePage must use the shared FilterChip")


if __name__ == "__main__":
    unittest.main()
