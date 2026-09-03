#!/usr/bin/env python3
"""A GroupButton's size animates for a press, never for a layout settling.

`GroupButton` animates `implicitWidth` and `implicitHeight` with the
click-bounce tier. Unconditionally, that animated any change - including the
one a settings window causes when it is created after its rows were built:
layouts never polish without a window, so every chip's width jumped to its
real value on the window's first frames, and the Behavior turned the jump
into ~20 frames of chips growing ~2.5px a frame while the row's Flow wrapped
and unwrapped behind them. That was the "options shaking" on the first open.

The bounce is press feedback, and the pointer is on the button when it
presses, so the gate is hover - the same one `AndroidQuickToggleButton` uses.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
BUTTON = ROOT / "modules/common/widgets/GroupButton.qml"


class GroupButtonSettleTests(unittest.TestCase):
    def setUp(self):
        self.source = BUTTON.read_text(encoding="utf-8")

    def _behavior_enabled(self, prop):
        block = re.search(r"Behavior on " + prop + r"\s*\{(.*?)\n\s*\}", self.source, re.S)
        self.assertIsNotNone(block, f"GroupButton must still animate {prop} for the bounce")
        enabled = re.search(r"enabled:\s*(.+)", block.group(1))
        self.assertIsNotNone(enabled, f"the {prop} Behavior must be gated")
        return enabled.group(1)

    def test_the_width_bounce_runs_only_under_the_pointer(self):
        self.assertIn("root.hovered", self._behavior_enabled("implicitWidth"))

    def test_the_height_bounce_runs_only_under_the_pointer(self):
        self.assertIn("root.hovered", self._behavior_enabled("implicitHeight"))

    def test_the_opt_out_still_exists(self):
        # Callers that never want the travel keep their switch.
        self.assertIn("root.enableImplicitWidthAnimation &&", self._behavior_enabled("implicitWidth"))
        self.assertIn("root.enableImplicitHeightAnimation &&", self._behavior_enabled("implicitHeight"))


if __name__ == "__main__":
    unittest.main()
