#!/usr/bin/env python3
"""Scores a widget's span change as motion rather than as a result.

`WidgetResizeMotionRuntimeTest.qml` builds real `PluginWidget`s on a real
`WidgetCanvas`, changes their span both ways a user can - the Size row's single
write and a live grip drag - and samples the widget's width *while* the change
is in flight. This module is the driver: it stands up a headless weston, points
throwaway XDG dirs at it, and fails the suite on any check the harness reports.

This is the half `test_widget_resize_grip_runtime.py` cannot answer. That
harness reads settled sizes on purpose, so it passes identically whether the
resize is animated or instant - and so would every static check, because a
`Behavior` handed a target that moves every frame compiles fine, never ticks,
and leaves the property snapping to its final value (AGENT.md: that is exactly
how the parallax opt-out shipped inert). A width that is already at its
destination 80ms into a 500ms move is the signature of that bug, and it is what
these checks fail on.

The grip is driven as well as the Size row for the same reason: it re-previews
on every mouse move and hands the host a fresh span object each time, which is
the shape that froze the position Behavior.

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
HARNESS = ROOT / "WidgetResizeMotionRuntimeTest.qml"
SOCKET = "wayland-imi-widget-resize-motion"


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
class WidgetResizeMotionRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-widget-resize-motion-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_a_span_change_is_animated_not_snapped(self):
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
        self.assertIn("[WidgetResizeMotion] failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        # The content's size follows the host's animating width, so a span
        # bound back through the item it sizes shows up here rather than as a
        # failed check - the widget would resize and never settle.
        self.assertNotIn("Binding loop", output,
                         f"the host tree grew a binding loop:\n{output}")


if __name__ == "__main__":
    unittest.main()
