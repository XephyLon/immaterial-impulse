#!/usr/bin/env python3
"""Drives the two notes surfaces against one store, with real mouse events.

`NotesSurfacesRuntimeTest.qml` builds the bundled notes plugin widget and the
overlay notes editor side by side and clicks their buttons through QtTest,
which works inside `qs -p`. This module is the driver: it stands up a headless
weston, points a throwaway XDG_STATE_HOME/XDG_CONFIG_HOME at it, and fails the
suite on any check the harness reports.

Headless weston rather than the caller's session because the harness opens a
window - running it on a real display would throw one across the user's
desktop. It implements no wlr-layer-shell, which is fine here: both surfaces
are ordinary Items, and nothing in this test needs a layer surface.

Skips when weston or qs is missing, as in CI.
"""

import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "NotesSurfacesRuntimeTest.qml"
SOCKET = "wayland-imi-notes-surfaces"


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
class NotesSurfacesRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-notes-surfaces-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_the_two_surfaces_share_one_store(self):
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
        self.assertIn("[NotesSurfaces] failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        # The harness deletes everything it made, so what is left on disk is
        # the store's own serialization - an array, not a plaintext blob.
        notes_file = self.home / "state" / "quickshell" / "user" / "notes.txt"
        self.assertTrue(notes_file.exists(), "the store was never written")
        self.assertEqual(json.loads(notes_file.read_text()), [])


if __name__ == "__main__":
    unittest.main()
