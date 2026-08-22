#!/usr/bin/env python3
"""Drives the real polkit prompt and reads its geometry and its feedback back.

`PolkitDialogRuntimeTest.qml` builds the real `PolkitContent` - the real
`WindowDialog`, `WindowDialogButtonRow`, `DialogButton` and `PasswordField` -
and asks it three things no source sweep can answer:

  * **Where the actions land.** Whether the action row sits in the dialog's
    content box is a `Layout` decision three components down. It did not: the
    row carried a negative `Layout.margins`, so the card's four paddings read
    23/23/23/15 and the confirming button's right edge sat 8px past the
    password field directly above it.
  * **Whether the buttons answer the pointer.** The fill a button shows is
    computed at runtime out of `Appearance`, so "it names a hover colour" is
    not "it changes colour". Both buttons are hovered with real mouse events
    and the change is scored in channel levels, with the other button as the
    control - a pair that both light is a global, not a pointer.
  * **Whether the field masks with the shell's glyphs.** The lock screen draws
    a Material shape per character and the dialog drew system bullets. The
    check counts the shapes after typing, and clicks the field first, because
    the glyph overlay is a `Flickable` over the real field and one that is not
    `enabled: false` eats exactly that click.

Headless weston, on a runtime dir and a session bus of the harness's own. The
polkit LAYER surface is deliberately out of scope: its gate is a read-only
alias onto the agent and a second agent cannot register for a session that
already has one, so nothing here says anything about the compositor's input
region. Skips when weston, qs or dbus-run-session is missing, as in CI.
"""

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "PolkitDialogRuntimeTest.qml"
SOCKET = "wayland-imi-polkit"

# A literal, never read back out of the harness's own output: a step list that
# shrinks must redden here instead of reporting `failures: 0` for a shorter run.
EXPECTED_CHECKS = 9


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
class PolkitDialogRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-polkit-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_the_prompt_lays_out_answers_the_pointer_and_masks_with_glyphs(self):
        env = dict(os.environ)
        # A runtime dir of the harness's own: everything this test starts talks
        # to its own weston and can never map a surface on the user's display.
        runtime = self.home / "runtime"
        runtime.mkdir(mode=0o700)
        env["XDG_RUNTIME_DIR"] = str(runtime)
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=900", "--height=700"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(_stop, weston)

        socket_path = Path(env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        self.assertTrue(socket_path.exists(), "headless weston never came up")

        env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        env["XDG_CONFIG_HOME"] = str(self.home / "config")
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")

        # dbus-run-session, not the inherited bus: the shell's polkit agent
        # talks to the system bus either way, but nothing else this harness
        # constructs may see the services the developer happens to be running.
        proc = subprocess.run(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[Polkit] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")


if __name__ == "__main__":
    unittest.main()
