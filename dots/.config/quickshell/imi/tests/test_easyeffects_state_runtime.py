#!/usr/bin/env python3
"""The EasyEffects toggle tells the truth, against a real shell and fake binaries.

services/EasyEffects.qml flips `active` optimistically when the toggle is
clicked - which is right for responsiveness and was the whole story: a launch
that failed (easyeffects gone, or crashing at startup) left the toggle saying
on for the rest of the session, with nothing ever re-checking. The fix
verifies against the real process list one grace period after every
enable()/disable(); this drives all three outcomes end to end:

- a failed launch is corrected back to off;
- a real launch survives the verify;
- a kill stays off.

The fake binaries keep state in a directory the harness controls: launching
succeeds only while `launch_ok` exists, a successful launch leaves a `running`
marker, `pidof` answers from it and `pkill` removes it.

Brings its own headless weston and a private session bus. Skips when weston
or qs is missing, as in CI.
"""

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "EasyEffectsStateRuntimeTest.qml"
SOCKET = "wayland-imi-easyeffects-state"

# The harness's check count, as a literal: a harness whose step list shrinks
# must redden here instead of reporting `failures: 0` for a shorter run.
EXPECTED_CHECKS = 11

RECORD = """#!/usr/bin/env bash
printf '%s\\n' "$(basename "$0") $*" >> "$EE_EXEC_LOG"
__BODY__
"""

EASYEFFECTS_BODY = """\
case "$1" in
  --hide-window)
    if [ -f "$EE_STATE_DIR/launch_ok" ]; then
      touch "$EE_STATE_DIR/running"
      exit 0
    fi
    exit 1
    ;;
esac
exit 0
"""

FLATPAK_BODY = """\
# `flatpak run` must fail like the native launch; `flatpak ps` and
# `flatpak info` answer for the pipeline and the availability probe.
case "$1" in
  info) exit 1 ;;
  ps) exit 1 ;;
  run) exit 1 ;;
  pkill) exit 1 ;;
esac
exit 1
"""

# Slow mode drives the stale-probe race: the answer is read BEFORE the sleep,
# so a probe that started before a toggle reports the pre-toggle world after
# the toggle has landed - exactly the answer the guard must discard.
PIDOF_BODY = """\
if [ -f "$EE_STATE_DIR/running" ]; then answer=0; else answer=1; fi
[ -f "$EE_STATE_DIR/slow" ] && sleep 0.3
exit "$answer"
"""

PKILL_BODY = """\
rm -f "$EE_STATE_DIR/running"
exit 0
"""


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


@unittest.skipUnless(_runtime_available(), "needs qs, weston and dbus-run-session on PATH")
class EasyEffectsStateRuntimeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.env = dict(os.environ)
        cls.env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        cls.env["WAYLAND_DISPLAY"] = SOCKET
        cls.env.pop("DISPLAY", None)
        cls.weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=800", "--height=600"],
            env=cls.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        socket_path = Path(cls.env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        if not socket_path.exists():
            _stop(cls.weston)
            raise AssertionError("headless weston never came up")

        cls.env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        cls.env["QT_QUICK_BACKEND"] = "software"

    @classmethod
    def tearDownClass(cls):
        _stop(cls.weston)

    def test_toggle_state_is_verified_against_reality(self):
        with tempfile.TemporaryDirectory(prefix="imi-easyeffects-") as directory:
            home = Path(directory)
            state = home / "ee-state"
            state.mkdir()
            bin_dir = home / "bin"
            bin_dir.mkdir()
            for name, body in (("easyeffects", EASYEFFECTS_BODY),
                               ("flatpak", FLATPAK_BODY),
                               ("pidof", PIDOF_BODY),
                               ("pkill", PKILL_BODY)):
                path = bin_dir / name
                path.write_text(RECORD.replace("__BODY__", body))
                path.chmod(0o755)

            env = dict(self.env)
            env["XDG_CONFIG_HOME"] = str(home / "config")
            env["XDG_STATE_HOME"] = str(home / "state")
            env["XDG_CACHE_HOME"] = str(home / "cache")
            env["PATH"] = f"{bin_dir}{os.pathsep}{env['PATH']}"
            env["EE_STATE_DIR"] = str(state)
            env["EE_EXEC_LOG"] = str(home / "exec.log")

            proc = subprocess.run(
                ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
                cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=120)
            output = proc.stdout + proc.stderr
            failed = [line for line in output.splitlines() if "FAIL" in line]
            self.assertEqual(failed, [], f"harness reported failures:\n{output}")
            self.assertIn(f"[EasyEffectsState] checks: {EXPECTED_CHECKS} failures: 0",
                          output, f"harness did not finish cleanly:\n{output}")


if __name__ == "__main__":
    unittest.main()
