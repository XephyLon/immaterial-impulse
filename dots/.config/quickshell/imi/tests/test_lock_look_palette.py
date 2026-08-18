#!/usr/bin/env python3
"""The lock's palette follows the Lockscreen tab, not just the session lock.

Edit Mode's Lockscreen tab is a FILTER on the desktop viewport (spec §1.4): it
switches the same layers to their locked inputs rather than drawing a second
copy of anything. Stage 9 switched every SOURCE that way - wallpaper, Wallpaper
Engine project, the islands host, the widget filter - and left the two places
that decide the PALETTE keyed on `GlobalStates.screenLocked` alone:
`MaterialThemeLoader.lockThemeActive` and Appearance's wallpaper quantizer.

So the tab drew the lock's wallpaper under the desktop's colours - a picture
the lock screen never shows, and the state the maintainer reported as "switching
to lockscreen does not change the widgets' colors".

`GlobalStates.lockLookActive` is the one spelling of "the lock's look is on
screen" and both sites now read it. This drives the tab and reads the gate back;
matugen never has to run, because what is under test is which wallpaper the
palette is taken FROM, not the palette itself.

Skips when weston, qs or dbus-run-session is missing, as in CI.
"""

import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "LockLookProbe.qml"
SOCKET = "wl-imi-locklook"

LINE = re.compile(r"\[LOCKLOOK\] (\S+[^:]*): lockLookActive=(\w+) lockThemeActive=(\w+)")


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


@unittest.skipUnless(_runtime_available(),
                     "needs qs, weston and dbus-run-session on PATH")
class LockLookPaletteTest(unittest.TestCase):
    def setUp(self):
        # Short prefix: a Wayland socket path is capped at 108 bytes including
        # the null, and a descriptive one under a long scratch dir dies in
        # weston before anything under test runs.
        self.home = Path(tempfile.mkdtemp(prefix="imil-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_the_tab_carries_the_palette_with_it(self):
        env = dict(os.environ)
        runtime = self.home / "rt"
        runtime.mkdir(mode=0o700)
        env["XDG_RUNTIME_DIR"] = str(runtime)
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=800", "--height=600"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(_stop, weston)

        socket_path = runtime / SOCKET
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
        self.assertIn("[LOCKLOOK] done", output, f"probe did not finish:\n{output}")

        states = {stage: (look == "true", theme == "true")
                  for stage, look, theme in LINE.findall(output)}
        for stage in ("desktop tab", "lock tab", "back"):
            self.assertIn(stage, states, f"probe skipped {stage}:\n{output}")

        self.assertEqual(
            states["desktop tab"], (False, False),
            f"the desktop tab is showing the lock's look:\n{output}")
        self.assertEqual(
            states["lock tab"], (True, True),
            f"the Lockscreen tab did not carry the palette with it. Both "
            f"`MaterialThemeLoader.lockThemeActive` and Appearance's wallpaper "
            f"quantizer must read `GlobalStates.lockLookActive`, or the tab "
            f"shows the lock's wallpaper under the desktop's colours.\n{output}")
        self.assertEqual(
            states["back"], (False, False),
            f"leaving the tab left the lock's palette applied:\n{output}")


if __name__ == "__main__":
    unittest.main()
