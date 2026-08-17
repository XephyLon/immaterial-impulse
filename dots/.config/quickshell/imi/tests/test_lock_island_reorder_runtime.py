#!/usr/bin/env python3
"""Drives the lock islands' reorder with real mouse events.

`LockIslandReorderRuntimeTest.qml` builds the REAL `LockSurface` with the real
`LockPreviewContext` and drags its slots, committing against the real
`Config.options.lock.islands.*` lists in a throwaway config. What only real
events can show: the press lands on the overlay's eater and `ReorderDragArea`
takes over past the threshold; the drop resolves over centres carrying holes
(invisible slots, the dragged one); the commit runs move semantics and the
`storedOrder` merge, so an id a newer shell stored survives; the password slot
loads no overlay and the same gesture over it moves nothing; and both cancel
paths - the ladder's `editReorderCancel` and the mode's exit - leave the
stored lists untouched.

Headless weston because the harness opens a window; weston implements no
wlr-layer-shell, so the real session lock surface is outside what this can
say. Skips when weston or qs is missing, as in CI.
"""

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "LockIslandReorderRuntimeTest.qml"
SOCKET = "wayland-imi-lock-islands"

# A literal, never read back out of the harness's own output: a step list that
# shrinks must redden here instead of reporting `failures: 0` for a shorter
# run.
EXPECTED_CHECKS = 12


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
class LockIslandReorderRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-lock-islands-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_the_islands_reorder_and_the_field_does_not(self):
        env = dict(os.environ)
        # A runtime dir of the harness's OWN, not the session's: everything
        # this test starts talks to its own weston and can never reach the
        # user's compositor - a lock-screen surface probed on the live display
        # locks the real session, and on this machine a real lock suspends
        # the laptop.
        runtime = self.home / "runtime"
        runtime.mkdir(mode=0o700)
        env["XDG_RUNTIME_DIR"] = str(runtime)
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=1500", "--height=700"],
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
        self.assertIn(f"[LockIslands] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")


if __name__ == "__main__":
    unittest.main()
