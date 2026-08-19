#!/usr/bin/env python3
"""The one-shot parallax revival, against a real config.json.

Wallpaper parallax was config-only for this shell's whole life: the knobs came
over from dots-hyprland but the code reading them left with the ii->pC theme
swap, so nothing has consumed them since. Every value an existing config
carries therefore predates the feature doing anything - it was never possible
to see what it did - and reviving the effect against those values would ship it
switched off for everyone who has ever written a config, which is everyone.

None of that is reachable from a unit test. The failure lives in the merge: the
QML defaults say true, the stored config says false, and the adapter's answer
is the one the shell runs on. So this launches a real shell against a seeded
throwaway config directory and reads the file back afterwards.

Needs a Wayland session and `qs` on PATH, so it skips in CI the same way the
other runtime harnesses do.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "ParallaxMigrationRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"

# A zoom nobody would pick by accident, so its survival is unambiguous.
TUNED_ZOOM = 1.42


# The harness prints how many checks it ran. This number is a literal rather
# than anything read back from that output: a harness whose step list shrinks
# must redden here instead of reporting `failures: 0` for a shorter run.
EXPECTED_CHECKS = 6


def _runtime_available():
    return bool(os.environ.get("WAYLAND_DISPLAY")) and all(shutil.which(binary) is not None
               for binary in ("qs", "dbus-run-session"))


@unittest.skipUnless(_runtime_available(),
                     "needs a Wayland session and qs on PATH")
class ParallaxMigrationRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-parallax-runtime-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        self.shell_config = self.config_home / "immaterial-impulse"
        self.shell_config.mkdir(parents=True)

    @property
    def config_file(self):
        return self.shell_config / "config.json"

    def seed(self, parallax):
        config = json.loads(SHIPPED_DEFAULT.read_text())
        # Keep the other migrations out of this one's way.
        config["migratedUpstreamSchema"] = True
        config.setdefault("background", {})["parallax"] = parallax
        self.config_file.write_text(json.dumps(config, indent=2))

    def launch(self, expected):
        env = dict(os.environ)
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["PARALLAX_EXPECT"] = expected
        proc = subprocess.run(
            # dbus-run-session, not the inherited DBUS_SESSION_BUS_ADDRESS: a
            # shell reading MPRIS, UPower or a portal off the developer's bus
            # measures their session rather than this tree.
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[Parallax] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")
        return output

    def stored(self):
        return json.loads(self.config_file.read_text())["background"]["parallax"]

    def test_dead_era_switches_are_turned_back_on(self):
        # Exactly the shape found on the author's machine: every switch off,
        # a hand-tuned zoom, and no marker.
        self.seed({
            "vertical": False,
            "autoVertical": False,
            "enableWorkspace": False,
            "enableSidebar": False,
            "workspaceZoom": TUNED_ZOOM,
            "widgetsFactor": 1.2,
        })
        self.launch("on")
        stored = self.stored()
        self.assertTrue(stored["enableWorkspace"])
        self.assertTrue(stored["enableSidebar"])
        self.assertTrue(stored["enable"])
        self.assertTrue(stored["migratedFromDeadCode"])

    def test_a_tuned_zoom_is_never_reset(self):
        # The switches are leftovers; the numbers might not be. A zoom cannot
        # turn the effect off on its own, so there is no reason to touch it.
        self.seed({
            "enableWorkspace": False,
            "workspaceZoom": TUNED_ZOOM,
            "widgetsFactor": 1.2,
        })
        self.launch("on")
        self.assertAlmostEqual(self.stored()["workspaceZoom"], TUNED_ZOOM, places=3)

    def test_a_deliberate_off_survives_once_the_marker_is_set(self):
        # After the migration has run, "off" is a real preference and must
        # stick - otherwise every launch overrides the user.
        self.seed({
            "enable": False,
            "enableWorkspace": False,
            "enableSidebar": False,
            "enableWidgets": False,
            "workspaceZoom": TUNED_ZOOM,
            "widgetsFactor": 1.2,
            "migratedFromDeadCode": True,
        })
        self.launch("off")
        stored = self.stored()
        self.assertFalse(stored["enable"])
        self.assertFalse(stored["enableWorkspace"])


if __name__ == "__main__":
    unittest.main()
