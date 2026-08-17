#!/usr/bin/env python3
"""Drives Edit Mode's desktop with real mouse events, at the mode's own scale.

`EditModeRuntimeTest.qml` builds a real `WidgetCanvas` with real
`PluginWidget`s on it, applies the same transform the background surface
applies - from the same module and the same tokens - and drags widgets around
inside it. This module is the driver: it stands up a headless weston, points
throwaway XDG dirs at it, and fails the suite on any check the harness reports.

`tst_edit_mode.qml` covers the arithmetic and `test_edit_mode_contract.py`
covers what the source says. Neither can answer the question the viewport turns
on: whether a gesture still lands where the pointer put it once the canvas is
drawn at a scale. The drag is hand-computed by mapping the pointer through the
moving widget into the canvas frame, so the transform is meant to cancel itself
out - and the last time that was assumed rather than measured, half a gesture
was being swallowed (d2ebb5aeb).

Headless weston rather than the caller's session because the harness opens a
window. It implements no wlr-layer-shell, so nothing about the background
*surface* is visible from here - the blur backdrop, the keyboard focus the
Escape ladder needs and the compositor's alpha map are all outside what any
harness can say.

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
HARNESS = ROOT / "EditModeRuntimeTest.qml"
SOCKET = "wayland-imi-edit-mode"


# The harness prints how many checks it ran. A literal rather than anything read
# back out of that output: a harness whose step list shrinks must redden here
# instead of reporting `failures: 0` for a shorter run.
EXPECTED_CHECKS = 30


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
class EditModeRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-edit-mode-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_the_desktop_edits_the_same_way_at_the_mode_s_scale(self):
        env = dict(os.environ)
        env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=1400", "--height=900"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(_stop, weston)

        socket_path = Path(env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        self.assertTrue(socket_path.exists(), "headless weston never came up")

        # This box's headless EGL has no driver, so force software rendering.
        env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        env["QT_QUICK_BACKEND"] = "software"
        env["XDG_CONFIG_HOME"] = str(self.home / "config")
        env["XDG_STATE_HOME"] = str(self.home / "state")

        proc = subprocess.run(["qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[EditMode] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        # A transform bound through the geometry it transforms shows up here
        # rather than as a failed check - the desktop would still shrink, it
        # would just never settle.
        self.assertNotIn("Binding loop", output,
                         f"the desktop tree grew a binding loop:\n{output}")


if __name__ == "__main__":
    unittest.main()
