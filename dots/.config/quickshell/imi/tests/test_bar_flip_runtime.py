#!/usr/bin/env python3
"""Scores a bar reflow as motion rather than as a result.

`BarFlipRuntimeTest.qml` builds real `BarGroup`s in the three arrangements the
bar's buckets use - near-edge, far-edge and a vertical strip - and takes a
widget out of each model, which is what an emptying tray or a switched-off
plugin does. It then samples where each surviving slot is DRAWN 80ms and 240ms
into the reflow.

That sampling is the whole point. Every settled check passes identically on the
teleport this replaces: a `Repeater` puts every slot in the right place either
way, and the difference is only ever visible in the frames in between. The
sibling shape is `WidgetResizeMotionRuntimeTest.qml`, which exists for exactly
the same reason on the desktop widgets' span change.

Four further things are scored because none of them are visible from a settled
position: a slot whose own coordinate never changed still travels (in a
far-edge bucket the section moves under it, and the idiom this was taken from
watches only the slot itself); a widget with no record snaps instead of flying
in from wherever it used to sit; a reorder drag in flight suppresses the
reposition, because the gesture reads slot centres through a `mapToItem` that
composes the transform; and the motion is along the bar only, at both
orientations.

Headless weston because the harness opens a window; weston implements no
wlr-layer-shell, so the bar's real surface and the real widget files are
outside what this can say. On a private session bus, because a harness that
inherits the developer's measures their session as well as this tree. Skips
when weston, qs or dbus-run-session is missing, as in CI.
"""

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "BarFlipRuntimeTest.qml"
SOCKET = "wayland-imi-bar-flip"

# A literal, never read back out of the harness's own output: a step list that
# shrinks must redden here instead of reporting `failures: 0` for a shorter
# run.
EXPECTED_CHECKS = 35


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def _runtime_available():
    return all(shutil.which(tool) is not None
               for tool in ("qs", "weston", "dbus-run-session"))


@unittest.skipUnless(_runtime_available(),
                     "needs qs, weston and dbus-run-session on PATH")
class BarFlipRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-bar-flip-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_a_bar_reflow_travels_instead_of_teleporting(self):
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

        proc = subprocess.run(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[BarFlip] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")


if __name__ == "__main__":
    unittest.main()
