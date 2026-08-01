#!/usr/bin/env python3
"""Structural guarantees for shared settings controls."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SharedWidgetContractsTest(unittest.TestCase):
    def test_config_switch_leaves_parent_spacing_to_its_container(self):
        source = (ROOT / "modules/common/widgets/ConfigSwitch.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("Layout.bottomMargin", source)


if __name__ == "__main__":
    unittest.main()
