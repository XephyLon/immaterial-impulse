#!/usr/bin/env python3
"""Drives the bar's in-place edit gesture with real mouse events.

`BarEditRuntimeTest.qml` builds the real stage-8 machinery - BarGroup's edit
loader, the eater, the badge, ReorderDragArea and BarEditController's commits
against real `Config.options.bar.layouts.*` - around synthetic slots, and
drags them. The named pair is the point: a drag ALONG the bar must reorder and
a drag ACROSS it must not, at both orientations, with the horizontal run first
as the control - the axis-inert comparison is how the vertical dock's reorder
shipped broken, and nothing but real events can see it (the layout is
perfectly plausible either way).

Every commit in the harness runs the visible-to-stored mapping over a stored
list carrying a hidden entry, so a reorder that eats hidden entries fails
here in the stored string rather than passing on the drawn one.

Headless weston because the harness opens a window; weston implements no
wlr-layer-shell, so the bar's real surface, its mustShow suspension and the
real widget files are all outside what this can say. Skips when weston or qs
is missing, as in CI.
"""

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "BarEditRuntimeTest.qml"
SOCKET = "wayland-imi-bar-edit"

# A literal, never read back out of the harness's own output: a step list that
# shrinks must redden here instead of reporting `failures: 0` for a shorter
# run.
EXPECTED_CHECKS = 17


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
class BarEditRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-bar-edit-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_the_bar_reorders_along_its_axis_and_only_along_it(self):
        env = dict(os.environ)
        env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=1000", "--height=1000"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(_stop, weston)

        socket_path = Path(env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        self.assertTrue(socket_path.exists(), "headless weston never came up")

        env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        env["QT_QUICK_BACKEND"] = "software"
        env["XDG_CONFIG_HOME"] = str(self.home / "config")
        env["XDG_STATE_HOME"] = str(self.home / "state")

        proc = subprocess.run(["qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[BarEdit] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")


if __name__ == "__main__":
    unittest.main()
