#!/usr/bin/env python3
"""A transparent-plated RippleButton must name its ripple tone.

The default colRipple is colLayer1Active - chosen for a button PLATED in
colLayer1, where the active tone contrasts. A transparent plate sits ON
some surface, usually colLayer1 itself, so the inherited default ripples
in the colour of its own floor and reads as nothing: 33 call sites had it
before the sweep (2026-08-31). This keeps the class at zero: transparent
background => explicit colRipple (or rippleEnabled: false).
"""
import re
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHELL = HERE.parent


def blocks(text):
    for m in re.finditer(r'\bRippleButton\s*\{', text):
        depth, j = 0, m.start()
        while j < len(text):
            if text[j] == '{':
                depth += 1
            elif text[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        yield text[m.start():j + 1]


class RippleToneTests(unittest.TestCase):
    def test_transparent_plates_name_their_ripple(self):
        offenders = []
        for path in sorted((SHELL / "modules").rglob("*.qml")):
            text = path.read_text(errors="replace")
            if "RippleButton" not in text:
                continue
            for block in blocks(text):
                head = block[:1200]
                transparent = ('colBackground: "transparent"' in head
                               or "colBackground: ColorUtils.transparentize" in head)
                if transparent and "colRipple" not in block and "rippleEnabled: false" not in block:
                    offenders.append(f"{path.relative_to(SHELL)}: {block.splitlines()[1].strip()[:60]}")
        self.assertEqual(offenders, [], "\n".join([
            "Transparent-plated RippleButtons inheriting the invisible default",
            "ripple - name a colRipple matching the hover family:",
            *(f"  {o}" for o in offenders),
        ]))


if __name__ == "__main__":
    unittest.main()
