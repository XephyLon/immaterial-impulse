#!/usr/bin/env python3
"""Source pins holding bar geometry where a unit test can reach it.

`tst_bar_geometry.qml` evaluates the real `Appearance.sizes.*` tokens and
proves the arithmetic. That only guards anything for as long as the call sites
actually *read* those tokens - an inline expression in Bar.qml or in one of the
badges is invisible to it, and inline is exactly where both bugs lived:

  - #98: `margins.bottom` was
        (enable && anchors.bottom) * -1 || cornerStyle === 3 ? 5 : 0
    and `||` binds tighter than `?:`, so the whole left-hand side was only the
    ternary's condition. A live dead-pixel workaround yielded +5 instead of -1.

  - #99: the standalone badges centred themselves in the whole bar, which is
    the group pill's centre only while the pill's two insets match. Hug's stop
    matching, and the badge went flush against one edge of the pill.

So these pins are about *where the arithmetic lives*, not about its result.
They reuse the structural QML reader from the background suppression pins
rather than grepping raw text, for the reason recorded there: a text pattern
over QML decays into one that matches nothing after any reformat.
"""
import re
import unittest
from pathlib import Path

from test_background_fullscreen_suppression import _qml_source

ROOT = Path(__file__).resolve().parents[1]
BAR = ROOT / "modules/imi/bar/Bar.qml"
BADGES = (
    ROOT / "modules/imi/bar/TimerPill.qml",
    ROOT / "modules/imi/bar/PrivacyIndicator.qml",
    ROOT / "modules/imi/bar/SubmapIndicator.qml",
)

# A margin that is nothing but one named token: `Appearance.sizes.barX`.
_TOKEN_ONLY = re.compile(r"^Appearance\.sizes\.(\w+)$")


class BarWindowMarginTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.qml = _qml_source(BAR)
        windows = cls.qml.elements("PanelWindow")
        assert len(windows) == 1, (
            f"expected exactly one PanelWindow in {BAR}, found {len(windows)}")
        cls.window = windows[0]
        groups = [b for b in cls.window.children
                  if b.kind == "group" and b.name == "margins"]
        assert len(groups) == 1, (
            f"expected exactly one `margins` group on the bar window, found {len(groups)}")
        cls.margins = dict(cls.qml.members(groups[0]))

    def test_the_file_parses(self):
        self.assertEqual(self.qml.unclosed, 0,
                         "unbalanced braces in Bar.qml - the pins below would "
                         "silently stop covering anything.")
        self.assertEqual(sorted(self.margins), ["bottom", "right", "top"],
                         "the bar window's margins should still be exactly these three")

    def test_every_margin_is_a_single_named_token(self):
        """No arithmetic here at all, which is what makes the trap unreachable.

        The precedence bug needed two things in one expression: a `?:` and a
        `||`. Admitting only a bare token reference means neither can be
        written in this position again, and it keeps the real expression in
        Appearance.qml where `tst_bar_geometry.qml` evaluates it for real.
        """
        for side, value in sorted(self.margins.items()):
            self.assertRegex(
                value.strip(), _TOKEN_ONLY,
                f"margins.{side} computes its own value ({value.strip()!r}). "
                "Put the arithmetic in an Appearance.sizes token so the unit "
                "test can evaluate it - inline is how `||` binding tighter "
                "than `?:` turned the dead-pixel workaround's -1 into +5.")

    def test_the_margins_are_the_tokens_the_unit_test_evaluates(self):
        """A token that no test knows about is no better than an inline one."""
        named = {}
        for side, value in self.margins.items():
            match = _TOKEN_ONLY.match(value.strip())
            named[side] = match.group(1) if match else value.strip()
        self.assertEqual(named,
                         {"top": "barDetachMargin",
                          "right": "barDeadPixelOverhang",
                          "bottom": "barBottomMargin"},
                         "tst_bar_geometry.qml evaluates these token names by "
                         "hand; renaming one here leaves it unevaluated.")


class StandaloneBadgeOffsetTests(unittest.TestCase):
    """Each badge has to be shifted onto its group pill's centre on both axes.

    A horizontal bar insets the group pill along its height and a vertical one
    along its width, so a badge that only corrects one axis is still off-centre
    in the other orientation.
    """

    def _pill(self, path):
        qml = _qml_source(path)
        pills = [b for b in qml.elements("Rectangle") if qml.element_id(b) == "pill"]
        self.assertEqual(len(pills), 1, f"expected one `pill` Rectangle in {path.name}")
        self.assertEqual(qml.unclosed, 0, f"unbalanced braces in {path.name}")
        return qml, dict(qml.members(pills[0]))

    def test_each_badge_shifts_onto_its_group_pills_centre(self):
        for path in BADGES:
            with self.subTest(badge=path.name):
                _, members = self._pill(path)
                self.assertEqual(
                    members.get("anchors.centerIn", "").strip(), "parent",
                    f"{path.name}'s pill should still centre itself in the badge root")
                for axis in ("anchors.verticalCenterOffset", "anchors.horizontalCenterOffset"):
                    value = members.get(axis)
                    self.assertIsNotNone(
                        value,
                        f"{path.name} never sets {axis}, so the badge stays centred "
                        "in the whole bar rather than in the group pill it sits in.")
                    self.assertIn(
                        "barStandalonePillOffset", value,
                        f"{path.name}'s {axis} does not read the shared offset "
                        f"({value.strip()!r}); the four corner styles disagree about "
                        "where the group pill's centre is.")

    def test_each_badge_takes_its_height_from_the_shared_token(self):
        """The badge's size and its position are one design decision.

        Deriving the height locally is how the three drifted apart before, and
        the concentricity the unit test proves only holds for the token pair.
        """
        for path in BADGES:
            with self.subTest(badge=path.name):
                _, members = self._pill(path)
                self.assertIn(
                    "barStandalonePillHeight", members.get("implicitHeight", ""),
                    f"{path.name}'s pill no longer sizes itself from "
                    "Appearance.sizes.barStandalonePillHeight.")


if __name__ == "__main__":
    unittest.main()
