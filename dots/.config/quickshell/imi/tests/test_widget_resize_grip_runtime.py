#!/usr/bin/env python3
"""Drives the grid resize grip with real mouse events.

`WidgetResizeGripRuntimeTest.qml` builds two real `PluginWidget`s on a real
`WidgetCanvas` - one whose manifest offers three spans, one that offers a single
one - and drags the bottom-right corner of each. This module is the driver: it
stands up a headless weston, points throwaway XDG dirs at it, and fails the
suite on any check the harness reports.

`test_widget_grip_lock.py` can only grep the bindings, and the qmltestrunner
suite cannot instantiate the host at all. Neither answers the question this
feature turns on: whether a press on the corner resizes the widget or *walks*
it, since `AbstractWidget`'s drag-to-move is the root MouseArea the grip sits
inside. The harness therefore scores the widget's position on every gesture,
not only its stored span, and the single-span widget - whose corner must move
it - is the control that keeps a run where events stopped arriving from reading
as a pass.

Headless weston rather than the caller's session because the harness opens a
window. It implements no wlr-layer-shell, so the Escape it delivers proves the
grip's key handling and not the background surface's keyboard focus, which only
a real layer surface can answer.

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
HARNESS = ROOT / "WidgetResizeGripRuntimeTest.qml"
SOCKET = "wayland-imi-widget-resize-grip"


# The harness prints how many checks it ran. This number is a literal rather
# than anything read back from that output: a harness whose step list shrinks
# must redden here instead of reporting `failures: 0` for a shorter run.
EXPECTED_CHECKS = 26


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
class WidgetResizeGripRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-widget-resize-grip-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_the_grip_resizes_without_moving_the_widget(self):
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
                              capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[WidgetResizeGrip] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        # A span bound back through the item it sizes shows up here rather than
        # as a failed check - the widget would still resize, just never settle.
        self.assertNotIn("Binding loop", output,
                         f"the host tree grew a binding loop:\n{output}")


if __name__ == "__main__":
    unittest.main()
