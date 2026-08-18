#!/usr/bin/env python3
"""The drawer's list gets the drawer's height; its chrome rows take what they need.

`EditModeDrawer`'s ColumnLayout holds three chrome rows - the "Add" header, the
section tabs, the bar's bucket picker - and one ListView per section. A Layout
nested in a Layout defaults to `Layout.fillHeight: true`, so each of those rows
fills unless it says otherwise, and they compete with the ListView, whose own
implicitHeight is 0.

That competition shipped in stage 5. The section tab row took 831px of a 936px
column, the widget list was left 24, and the toggled chip - whose radius is
`height / 2` - painted an 831px stadium down the whole panel with the list
invisible behind it. Every binding in the file was individually right; the
failure was the distribution, and the only place it appeared was on screen.

Headless weston with its own runtime dir and a private session bus, like every
other harness here: this builds the real `EditModeChromeContent`, and the numbers
it reads must not depend on the developer's session. Skips when weston, qs or
dbus-run-session is missing, as in CI.
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
HARNESS = ROOT / "EditModeDrawerLayoutProbe.qml"
SOCKET = "wl-imi-drawer"

# The list must get most of the column. Not "more than the rows" - that is true
# at 300px too, and 300px of list under 600px of chrome is the same defect one
# size down.
MINIMUM_LIST_SHARE = 0.75
# A chrome row is a row of chips: one line of them, never a panel.
MAXIMUM_ROW_HEIGHT = 120

CHILD = re.compile(r"\[DRAWER\] child (\S+) h=(\d+)")
COLUMN = re.compile(r"\[DRAWER\] column h=(\d+)")


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
class EditModeDrawerLayoutTest(unittest.TestCase):
    def setUp(self):
        # A SHORT prefix, deliberately: a Wayland socket path is capped at 108
        # bytes including the null, and the scratch dirs these runs get are
        # long enough that a descriptive prefix pushes weston past it - the
        # failure is `socket path ... exceeds 108 bytes`, from weston, before
        # anything under test has run.
        self.home = Path(tempfile.mkdtemp(prefix="imid-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_the_list_gets_the_column_and_the_chrome_rows_do_not(self):
        env = dict(os.environ)
        runtime = self.home / "rt"
        runtime.mkdir(mode=0o700)
        env["XDG_RUNTIME_DIR"] = str(runtime)
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=1500", "--height=1200"],
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
        self.assertIn("[DRAWER] done", output, f"probe did not finish:\n{output}")

        column = COLUMN.search(output)
        self.assertIsNotNone(column, f"probe found no column:\n{output}")
        column_height = int(column.group(1))
        self.assertGreater(column_height, 400,
                           f"the drawer's column is not open:\n{output}")

        children = [(name, int(height)) for name, height in CHILD.findall(output)]
        self.assertTrue(children, f"probe listed no children:\n{output}")

        lists = [height for name, height in children if "ListView" in name]
        self.assertTrue(lists, f"the widgets section shows no list:\n{output}")
        share = max(lists) / column_height
        self.assertGreaterEqual(
            share, MINIMUM_LIST_SHARE,
            f"the drawer's list got {share:.0%} of its {column_height}px column "
            f"and needs at least {MINIMUM_LIST_SHARE:.0%}. A chrome row is "
            f"filling: a Layout nested in a Layout defaults to "
            f"Layout.fillHeight true, so every row in that column must state "
            f"`Layout.fillHeight: false`.\n{output}")

        for name, height in children:
            if "ListView" in name:
                continue
            self.assertLessEqual(
                height, MAXIMUM_ROW_HEIGHT,
                f"{name} is {height}px tall in a {column_height}px column - a "
                f"chrome row is one line of chips, and a filling one paints "
                f"its toggled chip as a full-height stadium "
                f"(`leftRadius: height / 2`).\n{output}")


if __name__ == "__main__":
    unittest.main()
