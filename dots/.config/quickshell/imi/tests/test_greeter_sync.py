#!/usr/bin/env python3
"""The greeter sync observes its inputs; it does not borrow triggers.

The SDDM greeter's inputs were refreshed only as a side effect of matugen's
color generation, so a WE scaling change never reached the login screen, and
the still - grabbed a second AFTER the config change announcing it - could be
produced after the copy and miss the greeter until the next color event.

GreeterSync.qml is the observer; these pin the wiring that would silently
regress: the observed leaves, the completion poke that closes the still race,
the debounce, and the privilege boundary (the shell runs the satellite's
user-side wrapper, never the root apply script).

See docs/superpowers/specs/2026-08-05-reactive-greeter-sync-design.md.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = (ROOT / "services/GreeterSync.qml").read_text()
BACKGROUND = (ROOT / "modules/imi/background/Background.qml").read_text()


def code_only(text):
    """Comment lines stripped - assert against THIS, never raw text (the
    comment explaining a rule necessarily names the thing it forbids)."""
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("//"))


class ObserverTests(unittest.TestCase):
    def test_the_greeter_relevant_leaves_are_observed(self):
        # Under-observation IS the staleness bug this service exists to end.
        # Scaling is the leaf whose staleness was reported by the user.
        for handler in ("onScalingChanged", "onActiveProjectChanged",
                        "onActivePathChanged", "onActiveTypeChanged",
                        "onActivePreviewChanged", "onWallpaperPathChanged"):
            self.assertIn(handler, SERVICE, f"leaf no longer observed: {handler}")

    def test_the_still_grab_pokes_the_sync_on_success(self):
        # The still is produced asynchronously, AFTER the config changes that
        # announced the wallpaper - the grab's completion is the event that
        # closes the copy-before-still race, and it must fire only on a write
        # that actually happened.
        # A block now, because the depth picker observes the same completion
        # (a project's still is what it segments) - the poke has to be the
        # first thing inside the guarded write, not merely near it.
        self.assertRegex(BACKGROUND,
                         r"if \(result\.saveToFile\(target\)\)\s*\{?\s*\n\s*GreeterSync\.request\(\)")

    def test_requests_are_debounced(self):
        # A wallpaper switch writes several observed leaves back to back.
        self.assertRegex(SERVICE, r"Timer \{\s*\n\s*id: debounce\s*\n\s*interval: \d+")
        self.assertIn("debounce.restart()", SERVICE)


class BoundaryTests(unittest.TestCase):
    def test_the_shell_runs_the_wrapper_not_the_root_script(self):
        # The satellite owns generation, gating and the privileged call. The
        # hub invoking the root apply script directly would bypass the diff
        # gate and put a sudo in the shell's own hot path.
        code = code_only(SERVICE)
        self.assertIn("sddm-theme-sync.sh", code)
        self.assertNotIn("sddm-theme-apply", code)
        self.assertNotIn("sudo", code)

    def test_a_missing_wrapper_is_a_silent_noop(self):
        # Machines without the SDDM theme, and satellites older than the
        # wrapper, must not log an error per wallpaper switch.
        self.assertRegex(code_only(SERVICE), r'\[ -f "\$\{root\.syncScript\}" \]')

    def test_nothing_fires_before_config_is_ready(self):
        # Startup writes the observed leaves while the config is still being
        # loaded; syncing the greeter to a half-loaded config is a downgrade.
        self.assertIn("if (!Config.ready) return", SERVICE)


if __name__ == "__main__":
    unittest.main()
