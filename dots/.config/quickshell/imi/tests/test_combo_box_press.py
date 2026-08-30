#!/usr/bin/env python3
"""A combo box answers a press the way every other control does - and its
popup stays put while it does.

Both combo boxes drew a colour swap and nothing else for as long as the shell
has had them; the maintainer noticed on 2026-08-30 ("Check the ripple effect
on this UI component in general. Doesn't seem to exist"). They cannot be
RippleButtons - a ComboBox opens its popup on its own release, a delegate
reports the click that chooses a row - so a PassiveRippleSurface sits under
each as its background: a RippleButton whose containment mask holds no area,
so it paints the hover, the ripple and the lift and never sees the press.

The lift is the part that bit back. Applied to the ComboBox ITSELF, the popup
- positioned by mapping through its parent's transform - opened where the
shrunken button was at the instant of release and stayed there ("a strange
displacement of the collapsed menu"). So the Scale goes on the three parts,
each about the control's centre, and the root carries no transform at all.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WIDGETS = ROOT / "modules/common/widgets"
COMBOS = ("StyledComboBox.qml", "StyledComboBoxSearch.qml")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


class PassiveSurfaceTests(unittest.TestCase):
    def test_the_surface_receives_no_input(self):
        button = strip_comments((WIDGETS / "RippleButton.qml").read_text())
        self.assertIn("containmentMask: root.passive ? nothing : null", button,
                      "a passive RippleButton must mask itself out of input delivery, "
                      "or it swallows the press its host needed")
        mask = re.search(r"Item\s*\{\s*id: nothing(.*?)\}", button, re.S)
        self.assertIsNotNone(mask, "the containment mask is no longer an Item - "
                                   "Qt ignores a QtObject with a JS contains()")
        self.assertRegex(mask.group(1), r"width:\s*0")
        self.assertRegex(mask.group(1), r"height:\s*0")

    def test_the_surface_never_lifts_itself(self):
        surface = strip_comments((WIDGETS / "PassiveRippleSurface.qml").read_text())
        self.assertIn("passive: true", surface)
        self.assertIn("transform: []", surface,
                      "the surface's own lift would leave its host's content standing still")


class ComboBoxTests(unittest.TestCase):
    def test_both_combo_boxes_press_on_a_passive_surface(self):
        for name in COMBOS:
            source = strip_comments((WIDGETS / name).read_text())
            self.assertRegex(source, r"background:\s*PassiveRippleSurface\s*\{",
                             f"{name}'s button has no ripple surface")
            self.assertRegex(source, r"delegate:\s*ItemDelegate\s*\{[\s\S]*?"
                                     r"background:\s*PassiveRippleSurface\s*\{",
                             f"{name}'s rows have no ripple surface")

    def test_the_lift_never_moves_the_popups_anchor(self):
        """No transform on the ComboBox root: the popup maps through it."""
        for name in COMBOS:
            source = strip_comments((WIDGETS / name).read_text())
            root_level = [line for line in source.splitlines()
                          if re.match(r" {4}transform:", line)]
            self.assertEqual(root_level, [], f"{name} transforms its root - the popup "
                                             f"will open where the pressed button was")
            for part in ("surface", "arrow", "content"):
                self.assertIn(f"transform: Lift {{ part: {part} }}", source,
                              f"{name}: the {part} does not take the lift")


if __name__ == "__main__":
    unittest.main()
