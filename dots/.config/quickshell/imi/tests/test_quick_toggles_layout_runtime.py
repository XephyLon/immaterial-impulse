#!/usr/bin/env python3
"""Editing the Android quick toggle layout must not scramble the buttons.

`DelegateChooser` picks a component when a delegate is *created* and never
re-picks for one that survives a model update. Paired with a model that keeps
delegates alive across updates, a row entry that changes in place keeps the
previous toggle's component - and so its `QuickToggleModel`, icon, name and
action - while carrying the new entry's data. The panel then shows, at each
position, whatever used to be there.

Nothing about that is visible in the config: the stored layout is right the
whole time, and a shell restart rebuilds every delegate and appears to fix it.
That combination is why this needs a real Quickshell rendering the real panel
rather than a unit test over the layout maths.

The cases that matter are the ones that reflow the rows. Rows are packed by
toggle size, so almost every edit moves entries across row boundaries, and an
entry that lands where a different toggle sat is exactly the in-place change
that goes unnoticed. A same-row reorder diffs as a move and was never broken -
covering only that is how the first attempt at this fix passed while the panel
stayed scrambled.

The same harness scores what the keyed model added on top of that: a reorder
must MOVE the tile's delegate, and the tile must be caught travelling to its new
slot rather than found already in it. A settled position is the same number
whether the tile animated or teleported, so the sample that can tell them apart
is taken mid-flight.

Needs a Wayland session and `qs` on PATH, so it skips in CI like the other
runtime harnesses.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "QuickTogglesLayoutRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"


# The harness prints how many checks it ran. This number is a literal rather
# than anything read back from that output: a harness whose step list shrinks
# must redden here instead of reporting `failures: 0` for a shorter run.
EXPECTED_CHECKS = 11


def _runtime_available():
    return bool(os.environ.get("WAYLAND_DISPLAY")) and shutil.which("qs") is not None


@unittest.skipUnless(_runtime_available(),
                     "needs a Wayland session and qs on PATH")
class QuickTogglesLayoutRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-quicktoggles-runtime-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        shell_config = self.config_home / "immaterial-impulse"
        shell_config.mkdir(parents=True)

        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        # Mixed sizes against a fixed column count, so the edits the harness
        # performs actually repack the rows. Equal-sized toggles would keep
        # every edit inside one row and hide the bug.
        config["sidebar"]["quickToggles"]["android"]["columns"] = 5
        config["sidebar"]["quickToggles"]["android"]["toggles"] = [
            {"type": "network", "size": 2},
            {"type": "idleInhibitor", "size": 1},
            {"type": "bluetooth", "size": 2},
            {"type": "audio", "size": 2},
            {"type": "mic", "size": 1},
            {"type": "nightLight", "size": 2},
        ]
        (shell_config / "config.json").write_text(json.dumps(config, indent=2))

    def test_layout_edits_keep_every_toggle_on_its_own_button(self):
        env = dict(os.environ)
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")

        proc = subprocess.run(["qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[QuickToggles] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")


if __name__ == "__main__":
    unittest.main()
