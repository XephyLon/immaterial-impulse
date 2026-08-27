#!/usr/bin/env python3
"""When the settings host builds its pages, and whether building them blocks.

`SettingsPageIncubationRuntimeTest.qml` builds the real `SettingsContent` in a
real window under this harness's own headless weston and session bus, and reads
back WHEN each page is built.

The defect it exists to refuse: the host assigned `active = true` to all fifteen
page loaders inside one `Qt.callLater` at `Config.ready`, which destroyed the
`active:` binding declared beside them and built ~24500 items in one turn of the
event loop. Measured on the harness's own 1ms heartbeat, interleaved A/B and
pooled over two sessions - six runs an arm, the first run of each arm discarded,
168 switches an arm:

    worst GUI-thread block, building the host   618ms  ->   63.5ms
                                          raw  599-631     59-69
    switch, synchronous part                  3ms med    -> 3ms med
    page ready after a switch (median / max)  1 / 5ms    -> 1 / 5ms
    block <=300ms of a click                  33 med, 34 p95, 2/168 over 40ms
                                           -> 33 med, 34 p95, 1/168 over 40ms
    block over a whole 900ms step             33 med, 2/168 over 40ms, max 108
                                           -> 33 med, 8/168 over 40ms, max 158

The block is the reproducible result. The click window separates nothing: what
the warm-up costs is eight blocks in 168 landing BETWEEN clicks rather than in
them, which is what the navigation hold exists for.

A `sync` timing around the write cannot see any of that: the old loop's cost
lands in the turn AFTER the write. Hence the heartbeat - the longest gap between
two of its ticks is how long the GUI thread was unavailable, which is what a
hitch is.

The `Binding loop` grep below is a second regression: the keep-alive term used
to read `item`, which is what `active` produces. It never fired while the eager
assignment was destroying the binding, and fired fourteen times per warm-up the
moment the binding was left alone - and Qt drops the re-evaluation rather than
erroring, so a page that should have been kept silently is not.

Brings its own headless weston (tests/nested_display.py) and its own session
bus (`dbus-run-session`). Skips when weston, qs or dbus-run-session are missing,
as in CI.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "SettingsPageIncubationRuntimeTest.qml"

# A literal, never read back out of the harness's own output: a step list that
# loses an entry must redden here instead of reporting `failures: 0` for a
# shorter run.
EXPECTED_CHECKS = 12


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class SettingsPageIncubationRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-settings-incubation-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        shell_config = self.home / "config" / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        # An empty config on purpose: every page then draws its defaults, so
        # what the harness measures is the host's own build schedule rather
        # than the maintainer's plugin list.
        (shell_config / "config.json").write_text(json.dumps({}, indent=2))

    def test_pages_are_incubated_rather_than_built_in_one_turn(self):
        env = nested_display.start(self, "settings-incubation", width=1200, height=800)
        env["XDG_CONFIG_HOME"] = str(self.home / "config")
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")

        # dbus-run-session, not the inherited bus: nothing this harness reads
        # may depend on what the developer happens to be running.
        proc = subprocess.run(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=300)
        output = proc.stdout + proc.stderr

        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[SettingsIncubation] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        loops = [line for line in output.splitlines() if "Binding loop" in line]
        self.assertEqual(loops, [], f"the page host logged a binding loop:\n{output}")


if __name__ == "__main__":
    unittest.main()
