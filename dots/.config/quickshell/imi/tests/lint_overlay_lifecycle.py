#!/usr/bin/env python3
"""The transient overlays hide after their leave motion and drop input before it.

`OverlayLifecycle` (modules/common/widgets) gives an overlay one scalar and a
surface lifetime that outlives its "open" flag by the leave tier. The two
ways a host defeats it, both recorded on the branch this was re-derived from:

- binding the surface's `active:` to the flag itself - the window is destroyed
  on the frame the flag drops and the leave never shows;
- leaving the window's input on for the whole lifetime - the leave motion is
  180 ms of dead desktop that eats clicks.

So for every overlay host that declares an `OverlayLifecycle`, its Loader /
LazyLoader is `active: <life>.alive`, and its PanelWindow carries a `mask:`
that follows the flag, not the lifetime. Both tiers exist in Appearance and
carry a curve with their duration.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APPEARANCE = ROOT / "modules/common/Appearance.qml"
HOSTS = [
    ROOT / "modules/imi/desktopMenu/DesktopMenu.qml",
    ROOT / "modules/imi/screenshotResult/ScreenshotResultPanel.qml",
    ROOT / "modules/imi/dropShelf/DropShelfPanel.qml",
]


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def offences(src, name="host"):
    found = []
    m = re.search(r"OverlayLifecycle\s*\{\s*id:\s*(\w+)", src)
    if not m:
        return [f"{name}: declares no OverlayLifecycle"]
    life = m.group(1)
    actives = re.findall(r"\bactive:\s*([^\n]+)", src)
    surface_actives = [a for a in actives if life in a or "GlobalStates." in a or "currentPath" in a]
    if not any(f"{life}.alive" in a for a in surface_actives):
        found.append(f"{name}: the surface's active: does not read {life}.alive - it hides on the flag and never shows the leave")
    for a in surface_actives:
        if f"{life}.alive" not in a and ("GlobalStates." in a or "currentPath" in a):
            found.append(f"{name}: active: {a.strip()} binds a surface to the flag, not the lifecycle")
    if not re.search(r"\bmask:\s*[^\n]*\?\s*null\s*:", src):
        found.append(f"{name}: no `mask: <flag> ? null : <empty Region>` - input would stay on through the leave")
    return found


class OverlayLifecycleLint(unittest.TestCase):
    def test_self_check_catches_the_two_traps(self):
        good = "OverlayLifecycle { id: life; wanted: GlobalStates.xOpen }\nLoader { active: life.alive }\nPanelWindow { mask: GlobalStates.xOpen ? null : noInput }"
        self.assertEqual(offences(good), [])
        flag = good.replace("active: life.alive", "active: GlobalStates.xOpen")
        self.assertTrue(any("never shows the leave" in o for o in offences(flag)))
        no_mask = good.replace("mask: GlobalStates.xOpen ? null : noInput", "")
        self.assertTrue(any("input would stay on" in o for o in offences(no_mask)))

    def test_every_lifecycle_host_hides_after_leave_and_drops_input_first(self):
        found = []
        for host in HOSTS:
            found += offences(_strip(host.read_text()), host.name)
        self.assertEqual(found, [], "\n".join(found))

    def test_the_tiers_exist_with_their_curves(self):
        src = _strip(APPEARANCE.read_text())
        for tier in ("overlayEnter", "overlayExit"):
            block = re.search(r"property QtObject %s: QtObject \{(.*?)\n        \}" % tier, src, re.S)
            self.assertIsNotNone(block, tier)
            body = block.group(1)
            self.assertRegex(body, r"duration:\s*motion\.scale\(\d+\)", f"{tier} goes through the motion policy")
            self.assertIn("bezierCurve: animationCurves.", body, f"{tier} names a curve")
        life = _strip((ROOT / "modules/common/widgets/OverlayLifecycle.qml").read_text())
        for tier in ("overlayEnter", "overlayExit"):
            self.assertIn(f"Appearance.animation.{tier}.duration", life)
            self.assertIn(f"Appearance.animation.{tier}.bezierCurve", life)


if __name__ == "__main__":
    unittest.main()
