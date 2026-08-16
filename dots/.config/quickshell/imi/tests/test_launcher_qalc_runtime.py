#!/usr/bin/env python3
"""Counts the qalc processes a typed launcher query really starts.

`LauncherQalcRuntimeTest.qml` builds the real `LauncherSearch` singleton,
reads its `results` the way the launcher list does, and types a query one
character at a time. This module is the driver: it stands up a headless
weston, puts a counting stub named `qalc` first on PATH, points throwaway XDG
dirs at a tempdir, and fails the suite on any check the harness reports.

Why a runtime harness and not another unit test: `tst_math_query.qml` can see
that `isMathQuery("firefox")` is false, and it would go on passing if the
launcher never consulted it. What was wrong was not a predicate but a call
site - `nonAppResultsTimer.restart()` sat inside the `results` binding, which
re-evaluates on every keystroke and again when `mathResult` arrives. The
number of processes that produces is a property of the binding graph, and the
only instrument that can see it is a real shell with a real PATH.

Measured on this tree before the gate landed: typing "firefox" (7 characters,
140ms apart) started **8** qalc processes - one per keystroke plus one more
from `mathResult` landing and re-firing the binding that had just spawned it.
After: 0. A math query still spawns, one per keystroke, and the duplicate is
gone as well: "2+2*10" went from 7 to 6.

The two cases are a pair on purpose. "Zero processes" is also what a harness
that never typed, or one whose `results` were never read, reports - so the
math case runs as the control, and the harness checks that the query arrived
and that the binding was live before it reports a count at all.

Skips when weston or qs is missing, as in CI.
"""

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "LauncherQalcRuntimeTest.qml"
SOCKET = "wayland-imi-launcher-qalc"

# Three per shape: the query arrived, the results binding was live, the spawn
# count landed in the band. A literal rather than anything read back out of the
# harness - a count taken from its own output would agree with itself.
EXPECTED_CHECKS = 3

QALC_STUB = """#!/bin/sh
echo "$@" >> "$QALC_COUNT_FILE"
echo "42"
"""


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def _runtime_available():
    return shutil.which("qs") is not None and shutil.which("weston") is not None


@unittest.skipUnless(_runtime_available(), "needs qs and weston on PATH")
class LauncherQalcRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-launcher-qalc-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

        bindir = self.home / "bin"
        bindir.mkdir()
        stub = bindir / "qalc"
        stub.write_text(QALC_STUB)
        stub.chmod(0o755)
        self.bindir = bindir

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
        self.env["PATH"] = f"{self.bindir}:{self.env['PATH']}"

    def _run(self, query, expect_min, expect_max):
        tally = self.home / f"tally-{query}"
        tally.write_text("")
        env = dict(self.env)
        env["QALC_COUNT_FILE"] = str(tally)
        env["QALC_QUERY"] = query
        env["QALC_EXPECT_MIN"] = str(expect_min)
        env["QALC_EXPECT_MAX"] = str(expect_max)

        proc = subprocess.run(["qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures for {query!r}:\n{output}")
        self.assertIn(f"[LauncherQalc] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly for {query!r}:\n{output}")

    def test_an_application_name_never_starts_a_calculator(self):
        self._run("firefox", 0, 0)

    def test_an_expression_still_reaches_the_calculator(self):
        # An upper bound rather than an exact number: the spawn is debounced by
        # `search.nonAppResultDelay`, so how many of the six prefixes survive
        # depends on scheduling. What must not regress is the floor - a gate
        # that answers "no" to everything is the other way to score zero here.
        self._run("2+2*10", 1, 6)


if __name__ == "__main__":
    unittest.main()
