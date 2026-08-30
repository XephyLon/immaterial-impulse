#!/usr/bin/env python3
"""Fail if a panel's body-scoped blur and its Hyprland layer rule disagree.

Scoping a panel's compositor blur to its painted body takes two edits in two
different files, and either one alone is broken in its own way:

  - `WindowBlurRegion` in the QML without `blur = false` in `rules.lua` leaves
    the catch-all whole-surface blur running, so the drop shadow keeps getting
    frosted (#82, #89) and the region changes nothing visible. The fix looks
    applied and isn't.
  - `blur = false` in `rules.lua` without a region in the QML is worse: the
    panel loses blur entirely rather than gaining a crisp shadow, and nothing
    errors - it just renders as flat unblurred transparency.

Neither half announces itself at runtime, and the QML suite can't see either,
so pin the pairing statically. This is the same two-sidedness as the
Config-schema/settings-page and validator/renderer pairs in AGENT.md: a change
to one side isn't done until the other side matches.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULES = ROOT.parents[1] / "hypr/hyprland/rules.lua"
MODULES = ROOT / "modules"

# The widget's own definition, which names itself without instantiating one.
WIDGET_DEFINITION = MODULES / "common/widgets/WindowBlurRegion.qml"

BLUR_DISABLED = re.compile(
    r'namespace\s*=\s*"([^"]+)"[^}]*}\s*,\s*blur\s*=\s*false')
PUBLISHES_REGION = re.compile(r'\bWindowBlurRegion\s*\{')
DECLARES_NAMESPACE = re.compile(r'WlrLayershell\.namespace:\s*"([^"]+)"')
IS_POPUP_WINDOW = re.compile(r'\bPopupWindow\s*\{')
IS_PANEL_WINDOW = re.compile(r'\bPanelWindow\s*\{')


def namespaces_with_blur_disabled():
    return {m.group(1) for m in BLUR_DISABLED.finditer(RULES.read_text())}


def namespaces_publishing_a_region():
    found = {}
    for path in sorted(MODULES.rglob("*.qml")):
        if path == WIDGET_DEFINITION:
            continue
        text = path.read_text(errors="ignore")
        if not PUBLISHES_REGION.search(text):
            continue
        rel = str(path.relative_to(ROOT))
        for match in DECLARES_NAMESPACE.finditer(text):
            found.setdefault(match.group(1), rel)
        if not DECLARES_NAMESPACE.search(text):
            found.setdefault(f"<no namespace in {rel}>", rel)
    return found


class PopupBlurRegionLint(unittest.TestCase):
    """A region published from a PopupWindow is accepted and does nothing.

    ext_background_effect binds a region to a *layer surface*. A PopupWindow is
    an xdg-popup, so `BackgroundEffect.blurRegion` on one is set without error,
    without warning, and without effect - the popup goes on being blurred whole
    by `blur_popups`, shadow and all.

    This cost a full write-deploy-look cycle on the tray menu before the
    inertness was visible, and nothing in the QML or the compositor says a word
    about it. Popups threshold their blur with `ignore_alpha` on the parent
    surface's namespace instead; see services/PopupBlurThreshold.qml.
    """

    def test_no_popup_window_publishes_a_blur_region(self):
        offenders = []
        for path in sorted(MODULES.rglob("*.qml")):
            if path == WIDGET_DEFINITION:
                continue
            text = path.read_text(errors="ignore")
            if not PUBLISHES_REGION.search(text):
                continue
            # A file holding both is not automatically wrong - the region may
            # belong to the PanelWindow - but it is worth a human look, and no
            # file does it today.
            if IS_POPUP_WINDOW.search(text) and not IS_PANEL_WINDOW.search(text):
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(
            offenders, [],
            "these publish a WindowBlurRegion from a PopupWindow, where it has "
            "no effect at all:\n  " + "\n  ".join(offenders)
            + "\nUse ignore_alpha on the parent surface's namespace instead.")


class BlurRegionPairingLint(unittest.TestCase):
    def setUp(self):
        self.disabled = namespaces_with_blur_disabled()
        self.publishers = namespaces_publishing_a_region()

    def test_every_published_region_has_its_layerrule_blur_turned_off(self):
        offenders = sorted(
            f"{ns} ({self.publishers[ns]}) publishes a WindowBlurRegion, but "
            f'rules.lua never sets blur = false for it'
            for ns in self.publishers if ns not in self.disabled)
        self.assertEqual(offenders, [], "\n".join(
            ["the whole-surface blur is still on, so the region fixes nothing:"]
            + offenders))

    # A surface with no translucent body has no region to scope a blur to;
    # its blur = false is the whole point, not half of a pairing.
    OPAQUE = {
        "quickshell:background": "the wallpaper layer is opaque edge to edge; "
                                 "blurring it was a fullscreen pass per frame for nothing",
    }

    def test_every_disabled_namespace_publishes_a_region(self):
        offenders = sorted(
            f"{ns} has blur = false in rules.lua, but no QML under modules/ "
            f"publishes a WindowBlurRegion for it"
            for ns in self.disabled if ns not in self.publishers and ns not in self.OPAQUE)
        self.assertEqual(offenders, [], "\n".join(
            ["these panels have no blur at all, not body-scoped blur:"]
            + offenders))

    def test_the_pairing_is_not_vacuous(self):
        """Guards the lint itself: both regexes match real source today, so a
        reformat that breaks either one fails here instead of passing silently
        by finding nothing on both sides."""
        self.assertTrue(RULES.is_file(), f"{RULES} is missing")
        self.assertTrue(self.disabled,
                        "no namespace in rules.lua matched the blur = false pattern")
        self.assertTrue(self.publishers,
                        "no QML under modules/ matched the WindowBlurRegion pattern")


if __name__ == "__main__":
    unittest.main()
