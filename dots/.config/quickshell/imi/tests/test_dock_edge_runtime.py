#!/usr/bin/env python3
"""Drives the dock's pinned-app reorder with real mouse events, on both axes.

`DockEdgeRuntimeTest.qml` builds a real `DragApps` and drags its slots at a
horizontal edge and at a vertical one. This module is the driver: it stands up
a headless weston, points throwaway XDG dirs at it, and fails the suite on any
check the harness reports.

Why a runtime harness and not another source contract: a vertical dock's
failure mode is not a layout that looks wrong. `test_dock_position_contract.py`
can see that the reorder names an axis, and `tst_dock_geometry.qml` can see
that the geometry answers for four edges - neither can see whether a press and
a drag actually move an icon past its neighbour. The reorder used to compare x
everywhere, and in a column every slot centre has the same x: the comparison is
a number against itself, so the icons refuse to move past each other with
nothing in any log.

The discriminating pair is a drag ALONG the strip (must reorder) and a drag
ACROSS it (must not). The horizontal edge runs first as the control, because
"nothing happened" is what a harness that stopped delivering events reports.

What it cannot answer: the harness opens a FloatingWindow, and weston
implements no wlr-layer-shell, so the dock's anchors, exclusive zone, reveal
push and the compositor's inferred slide direction are all invisible to it -
along with everything that is a look rather than a behaviour. Those are
`hyprctl layers -j` plus `hyprctl monitors -j`, against the baseline recorded
in the design doc.

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
HARNESS = ROOT / "DockEdgeRuntimeTest.qml"
SOCKET = "wayland-imi-dock-edge"


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
class DockEdgeRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-dock-edge-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_the_reorder_follows_the_axis_the_slots_run_along(self):
        env = dict(os.environ)
        env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=900", "--height=900"],
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
        self.assertIn("[DockEdge] failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        # A size bound back through the item it measures shows up here rather
        # than as a failed check: the strip would still reorder, it would just
        # never settle, and NaN geometry in this tree is a pegged core.
        self.assertNotIn("Binding loop", output,
                         f"the dock tree grew a binding loop:\n{output}")


if __name__ == "__main__":
    unittest.main()
