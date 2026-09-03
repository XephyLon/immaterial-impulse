#!/usr/bin/env python3
"""The button's mask layer is on only while a ripple is drawn.

`RippleButton` clips its expanding ripple to the rounded corners with an
`OpacityMask` on the background's `layer`. That layer was always on: an
offscreen texture and a render pass of its own for every button, ripple or
not - and this button is in every row, chip and sidebar entry of the shell.
Measured in a nested Hyprland, the settings window's first frame synced ~2,700
elements into 946 draw batches with it on and blocked the GUI thread 165 ms;
gating the layer on hover-or-ripple took that to 121 ms and halved the batches
before anything else changed.

At rest the background is a plain rounded `Rectangle` drawn directly; the
layer comes up on hover, so the texture exists before the press lands, and
stays while a ripple is still fading.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
BUTTON = ROOT / "modules/common/widgets/RippleButton.qml"


class RippleLayerGateTests(unittest.TestCase):
    def setUp(self):
        self.source = BUTTON.read_text(encoding="utf-8")

    def test_the_mask_layer_is_not_always_on(self):
        self.assertNotRegex(self.source, r"^\s*layer\.enabled:\s*true\s*$",
                            "an always-on layer is a render target per button, ripple or not")

    def test_the_layer_follows_hover_and_the_ripple(self):
        gate = re.search(r"^\s*layer\.enabled:\s*(.+)$", self.source, re.M)
        self.assertIsNotNone(gate, "the background must still declare a layer for the ripple's mask")
        expr = gate.group(1)
        # Hover first: the texture is allocated before the press, so the first
        # ripple on a button does not pay for it. The ripple's own opacity
        # second: a ripple fading after the pointer left is still clipped.
        self.assertIn("root.hovered", expr)
        self.assertIn("ripple.opacity > 0", expr)

    def test_the_effect_is_still_the_corner_mask(self):
        effects = re.findall(r"^\s*layer\.effect:\s*(\w+)", self.source, re.M)
        self.assertEqual(effects, ["OpacityMask"],
                         "the gate changes WHEN the layer is on, not what it does")


if __name__ == "__main__":
    unittest.main()
