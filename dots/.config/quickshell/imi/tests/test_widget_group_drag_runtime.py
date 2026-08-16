#!/usr/bin/env python3
"""Drives marquee multi-select and group drag with real mouse events.

`WidgetGroupDragRuntimeTest.qml` builds five real `PluginWidget`s on a real
`WidgetCanvas` and rubber-bands, group-drags, clamps and deselects them through
QtTest, which works inside `qs -p`. This module is the driver: it stands up a
headless weston, points throwaway XDG dirs at it, and fails the suite on any
check the harness reports.

The source contract in `test_widget_group_selection.py` can only grep the
bindings. It cannot answer the questions that matter - whether the marquee
picks exactly the widgets under it, whether a group drag preserves the
cluster's offsets at a screen edge, and whether every member ends the gesture
with a live binding and a persisted position. Only real events can.

Headless weston rather than the caller's session because the harness opens a
window. It implements no wlr-layer-shell, so this proves nothing about the
`PanelWindow` the real `Background.qml` puts the canvas on - the widget tree,
the canvas and the marquee are ordinary Items and are what this exercises.

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
HARNESS = ROOT / "WidgetGroupDragRuntimeTest.qml"
SOCKET = "wayland-imi-widget-group-drag"


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
class WidgetGroupDragRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-widget-group-drag-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_marquee_selection_and_group_drag(self):
        env = dict(os.environ)
        env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=1200", "--height=800"],
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
        self.assertIn(f"[WidgetGroupDrag] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        # A follower whose x binding died mid-group-drag, or a halo that got
        # anchored into a cycle, shows up here rather than as a failed check.
        self.assertNotIn("Binding loop", output,
                         f"the host tree grew a binding loop:\n{output}")


if __name__ == "__main__":
    unittest.main()
