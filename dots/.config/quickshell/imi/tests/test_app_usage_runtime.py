#!/usr/bin/env python3
"""The launch-history store, against a real file and the real ranking.

`AppUsageRuntimeTest.qml` builds the real `AppUsage` singleton and the real
`AppSearch` ranking over the machine's own desktop entries. This module is the
driver: headless weston, a throwaway XDG_STATE_HOME, and a look at the file
afterwards.

Three things live here that `tests/tst_frecency.qml` cannot reach, and all
three are the reasons this feature writes to a user's disk on every launch:

  - a launch recorded in one shell is still there in the next one, which is
    the whole claim of persisting anything;
  - the ranking is actually wired to the store. `AppSearch` would pass every
    unit test in the suite while ignoring `AppUsage` entirely, so the record
    case takes a query whose first two results are close, launches the second
    one forty times, and requires the order to change;
  - a corrupt store degrades to plain match-order ranking rather than breaking
    search. That path is a `FileView` load, a parse that answers null and a
    fallback - three components, none of which the pure functions see.

The pair-finding loop is deliberate. The boost is capped at 2x a match score,
so two results that differ by more than that legitimately do not flip; the
harness looks for a pair where the question is answerable instead of assuming
the first query produces one.

Skips when weston or qs is missing, as in CI.
"""

import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "AppUsageRuntimeTest.qml"
SOCKET = "wayland-imi-app-usage"

# Per shape, in the order the harness runs them.
EXPECTED_CHECKS = {"record": 5, "reload": 3, "corrupt": 4}

HOUR_MS = 60 * 60 * 1000


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def _runtime_available():
    return all(shutil.which(binary) is not None
               for binary in ("qs", "weston", "dbus-run-session"))


@unittest.skipUnless(_runtime_available(), "needs qs and weston on PATH")
class AppUsageRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-app-usage-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

        self.env = dict(os.environ)
        self.env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        self.env["WAYLAND_DISPLAY"] = SOCKET
        self.env.pop("DISPLAY", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=900", "--height=900"],
            env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(_stop, weston)

        socket_path = Path(self.env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        self.assertTrue(socket_path.exists(), "headless weston never came up")

        # This box's headless EGL has no driver, so force software rendering.
        self.env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        self.env["QT_QUICK_BACKEND"] = "software"
        self.env["XDG_CONFIG_HOME"] = str(self.home / "config")
        self.env["XDG_STATE_HOME"] = str(self.home / "state")
        self.env["XDG_CACHE_HOME"] = str(self.home / "cache")

        # Qt's StateLocation is $XDG_STATE_HOME/<app>, i.e. .../state/quickshell.
        self.store_path = self.home / "state" / "quickshell" / "user" / "app-usage.json"

    def _run(self, case, **extra):
        env = dict(self.env)
        env["APPUSAGE_CASE"] = case
        env.update(extra)
        proc = subprocess.run(
            # dbus-run-session, not the inherited DBUS_SESSION_BUS_ADDRESS: a
            # shell reading MPRIS, UPower or a portal off the developer's bus
            # measures their session rather than this tree.
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures for {case!r}:\n{output}")
        self.assertIn(f"[AppUsage] checks: {EXPECTED_CHECKS[case]} failures: 0", output,
                      f"harness did not finish cleanly for {case!r}:\n{output}")
        return output

    def _seed(self, payload):
        self.store_path.parent.mkdir(parents=True, exist_ok=True)
        self.store_path.write_text(payload)

    def test_a_launch_is_recorded_and_reranks_the_results(self):
        self._run("record")
        self.assertTrue(self.store_path.exists(), "nothing was written to the store")
        stored = json.loads(self.store_path.read_text())
        self.assertIn("apps", stored)
        self.assertEqual(len(stored["apps"]), 1, f"one app should be recorded: {stored}")
        entry = next(iter(stored["apps"].values()))
        self.assertEqual(entry["total"], 40)
        self.assertLessEqual(len(entry["launches"]), 32, "the retained timestamps are capped")

    def test_a_recorded_launch_survives_the_shell_that_recorded_it(self):
        now_ms = int(time.time() * 1000)
        self._seed(json.dumps({
            "version": 1,
            "apps": {"seeded.desktop": {"launches": [now_ms - HOUR_MS], "total": 7}},
        }))
        self._run("reload", APPUSAGE_SEEDED_ID="seeded.desktop")

    def test_a_corrupt_store_falls_back_to_plain_match_ranking(self):
        self._seed("{ this is not the launch history you are looking for")
        self._run("corrupt")

    def test_an_empty_store_file_is_treated_as_no_history(self):
        # A zero-length file is what an interrupted write used to be able to
        # leave behind, which is why `atomicWrites` is on - but the reader must
        # survive one however it got there.
        self._seed("")
        self._run("corrupt")


if __name__ == "__main__":
    unittest.main()
