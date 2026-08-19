#!/usr/bin/env python3
"""Drives the widget-to-widget edge snap with real mouse events.

`WidgetEdgeSnapRuntimeTest.qml` builds five real `PluginWidget`s on a real
`WidgetCanvas` and drags one toward another's edge through QtTest, which works
inside `qs -p`. This module is the driver: it stands up a headless weston,
points throwaway XDG dirs at it, and fails the suite on any check the harness
reports.

`tst_edge_snap.qml` proves the module's arithmetic - the candidate set, the
perpendicular filter, the two-threshold hold. What only real events can prove
is the wiring: the hold overriding the lattice inside the live drag Binding,
the hysteresis fed the shadow position rather than the rendered one, the
canvas's guide standing at the neighbour's edge, the perpendicular filter
refusing a distant neighbour on a real drag, and a group drag's leader
snapping while its follower keeps both offsets. The anchor sits off the 12px
lattice on purpose, so every edge landing the harness asserts is a position
the lattice snap cannot produce by coincidence.

Headless weston rather than the caller's session because the harness opens a
window. It implements no wlr-layer-shell, so this proves nothing about the
`PanelWindow` the real `Background.qml` puts the canvas on - the widget tree,
the canvas and the guides are ordinary Items and are what this exercises.

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
HARNESS = ROOT / "WidgetEdgeSnapRuntimeTest.qml"
SOCKET = "wayland-imi-widget-edge-snap"


# The harness prints how many checks it ran. This number is a literal rather
# than anything read back from that output: a harness whose step list shrinks
# must redden here instead of reporting `failures: 0` for a shorter run.
EXPECTED_CHECKS = 17


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
class WidgetEdgeSnapRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-widget-edge-snap-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_edge_snap_acquire_hold_and_release(self):
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

        proc = subprocess.run(
            # dbus-run-session, not the inherited DBUS_SESSION_BUS_ADDRESS: a
            # shell reading MPRIS, UPower or a portal off the developer's bus
            # measures their session rather than this tree, and a harness that
            # passes everywhere except on the maintainer's machine is the
            # failure this costs nothing to prevent.
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[WidgetEdgeSnap] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        self.assertNotIn("Binding loop", output,
                         f"the host tree grew a binding loop:\n{output}")


if __name__ == "__main__":
    unittest.main()
