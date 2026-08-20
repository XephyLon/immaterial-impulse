#!/usr/bin/env python3
"""The motion multiplier and the reduce-motion floor, against a real config.

tests/tst_motion_policy.qml pins the arithmetic. This pins the wiring, which is
where a multiplier goes wrong: the surveyed fork this was taken from has one,
and it silently does nothing for about half of that shell because the call
sites do not route through the tokens it scales. Ours reaches ~700 call sites
only if every tier in Appearance.qml is actually scaled - and eight of the
twelve tiers state their base as a literal while four read it out of
animationCurves, so a scaling applied to one spelling and not the other is the
realistic miss and is invisible in review.

Two things are checked that a unit test cannot reach:

  - the stored `config.json` value reaches the catalogue at all (the QML
    default and the adapter's merged answer are different numbers, and the
    adapter's is the one the shell runs on);
  - a multiplier BELOW the sanctioned range does not reach the reduce-motion
    floor. That is the whole reason the floor is a separate named state - a
    hand-edited config, a preset written by an older build, or a slider one
    notch further left must not be able to switch motion off, and must not be
    able to switch it back on either.

Needs a Wayland session and `qs` on PATH, so it skips in CI the same way the
other runtime harnesses do.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nested_display  # noqa: E402
HARNESS = ROOT / "MotionMultiplierRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"

# One per value the harness reads, plus the two stagger helpers. A literal
# rather than anything read back out of the harness's own output: `failures: 0`
# is also what a harness that ran nothing prints.
EXPECTED_CHECKS = 7

# (multiplier, reduceMotion, elementMove, elementMoveFaster, press, velocity, stagger)
#
# Every number here is worked out by hand from the bases in Appearance.qml
# (elementMove 500, elementMoveFaster 150, press 150, velocity 650, stagger
# step 0.2 * 200 = 40) rather than from motion_policy.js, so a change to the
# policy has to be re-justified here instead of agreeing with itself.
CASES = [
    ("unscaled", 1.0, False, 500, 150, 150, 650, 40),
    ("doubled", 2.0, False, 1000, 300, 300, 325, 80),
    # 0.0 is below MULTIPLIER_MIN. It must clamp to 0.5 - NOT collapse to the
    # floor, which is what the surveyed fork's `<= 0.25` threshold would do.
    ("below the sanctioned range", 0.0, False, 250, 75, 75, 1300, 20),
    ("reduce motion", 1.0, True, 0, 0, 0, 100000, 0),
    # The state outranks the slider in both directions: a user who has asked
    # for reduced motion does not get it undone by a fast multiplier.
    ("reduce motion beats a fast multiplier", 2.5, True, 0, 0, 0, 100000, 0),
]


def _runtime_available():
    return nested_display.available()


@unittest.skipUnless(_runtime_available(),
                     "needs qs, weston and dbus-run-session on PATH")
class MotionMultiplierRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-motion-runtime-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        self.shell_config = self.config_home / "immaterial-impulse"
        self.shell_config.mkdir(parents=True)

    def seed(self, multiplier, reduce_motion):
        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        appearance = config.setdefault("appearance", {})
        appearance["motion"] = {
            "multiplier": multiplier,
            "reduceMotion": reduce_motion,
        }
        (self.shell_config / "config.json").write_text(json.dumps(config, indent=2))

    def launch(self, move, faster, press, velocity, stagger):
        env = nested_display.start(self, "motion")
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["MOTION_EXPECT_MOVE"] = str(move)
        env["MOTION_EXPECT_FASTER"] = str(faster)
        env["MOTION_EXPECT_PRESS"] = str(press)
        env["MOTION_EXPECT_VELOCITY"] = str(velocity)
        env["MOTION_EXPECT_STAGGER"] = str(stagger)
        proc = subprocess.run(
            # dbus-run-session, not the inherited DBUS_SESSION_BUS_ADDRESS: a
            # shell reading MPRIS, UPower or a portal off the developer's bus
            # measures their session rather than this tree.
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[Motion] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

    def test_every_tier_follows_the_stored_multiplier(self):
        for name, multiplier, reduce_motion, *expected in CASES:
            with self.subTest(case=name):
                self.setUp()
                self.seed(multiplier, reduce_motion)
                self.launch(*expected)


if __name__ == "__main__":
    unittest.main()
