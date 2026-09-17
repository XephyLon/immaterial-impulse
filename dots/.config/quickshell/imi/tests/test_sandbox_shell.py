#!/usr/bin/env python3
"""The review sandbox's stop leaves nothing of the sandbox behind.

`tests/sandbox/sandbox_shell.sh stop` killed the pid it had recorded for the
shell, and that pid was the background SUBSHELL of `cd "$ROOT" && qs ... &`,
not the shell: the shell survived whenever it did not die with the nested
compositor, kept its own render loop going, and every later CPU reading of "the
sandbox shell" by `pgrep -n` could land on it (a review round's idle figures
swung 10x between starts for that reason). The script is driven here against
fake `Hyprland`, `dbus-run-session` and `qs` binaries - the fake shell ignores
SIGTERM, as a shell stuck in teardown does - so the check runs anywhere.
"""
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tests" / "sandbox" / "sandbox_shell.sh"

FAKE_HYPRLAND = """#!/usr/bin/env python3
import os, socket, time
sig = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr", "fakesig")
os.makedirs(sig, exist_ok=True)
a = socket.socket(socket.AF_UNIX); a.bind(os.path.join(sig, ".socket.sock"))
b = socket.socket(socket.AF_UNIX); b.bind(os.path.join(os.environ["XDG_RUNTIME_DIR"], "wayland-1"))
time.sleep(600)
"""
FAKE_DBUS = """#!/usr/bin/env bash
[ "$1" = "--" ] && shift
export DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent
exec "$@"
"""
# The shell: named quickshell in its own cmdline (the real launcher execs the
# binary), deaf to SIGTERM.
FAKE_QS = """#!/usr/bin/env bash
setsid -f bash -c 'exec -a fake-helper sleep 600'
exec -a quickshell python3 -c 'import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(600)'
"""


def shells_of(sb):
    return session_of(sb, b"quickshell")


def session_of(sb, prefix=b""):
    """Every process started inside the sandbox, found by its environment."""
    want = f"XDG_CONFIG_HOME={sb}/config".encode()
    found = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            env = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
            cmd = Path(f"/proc/{pid}/cmdline").read_bytes()
        except OSError:
            continue
        if want in env and cmd.startswith(prefix):
            found.append(int(pid))
    return found


class SandboxStopTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="imi-sbt-")
        t = Path(self.tmp.name)
        self.bin = t / "bin"; self.bin.mkdir()
        for name, body in (("Hyprland", FAKE_HYPRLAND), ("dbus-run-session", FAKE_DBUS), ("qs", FAKE_QS)):
            p = self.bin / name; p.write_text(body); p.chmod(0o755)
        self.root = t / "shell"; (self.root / "defaults").mkdir(parents=True)
        (self.root / "defaults" / "config.json").write_text("{}")
        self.sb = t / "sb"
        self.parent_run = t / "parent"; self.parent_run.mkdir(mode=0o700)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        XDG_RUNTIME_DIR=str(self.parent_run), WAYLAND_DISPLAY="wayland-parent")

    def tearDown(self):
        for pid in session_of(self.sb):
            os.kill(pid, signal.SIGKILL)
        subprocess.run(["bash", str(SCRIPT), "stop", str(self.sb)], env=self.env, capture_output=True, timeout=30)
        self.tmp.cleanup()

    def start(self):
        r = subprocess.run(["bash", str(SCRIPT), "start", str(self.root), str(self.sb)],
                           env=self.env, capture_output=True, text=True, timeout=60)
        self.assertIn("sandbox up", r.stdout, r.stdout + r.stderr)
        for _ in range(40):
            if shells_of(self.sb):
                break
            time.sleep(0.25)

    def recorded_pid(self):
        for line in (self.sb / "env").read_text().splitlines():
            if "SANDBOX_QS_PID=" in line:
                return int(line.split("SANDBOX_QS_PID=")[1])
        self.fail("no SANDBOX_QS_PID in the env file")

    def test_the_recorded_pid_is_the_shell(self):
        self.start()
        self.assertEqual(shells_of(self.sb), [self.recorded_pid()],
                         "the env file names the shell process, not a subshell around it")

    def test_stop_leaves_no_shell_behind(self):
        self.start()
        self.assertTrue(shells_of(self.sb), "the fake shell is running")
        r = subprocess.run(["bash", str(SCRIPT), "stop", str(self.sb)], env=self.env,
                           capture_output=True, text=True, timeout=30)
        self.assertIn("sandbox stopped", r.stdout)
        self.assertEqual(shells_of(self.sb), [], "a shell deaf to SIGTERM is still killed")

    def test_stop_ends_the_whole_session(self):
        # The shell starts helpers of its own (tray watchdog, monitors, a
        # keyring, a D-Bus): they outlived every stop, 274 of them after a
        # day of reviews, and a watchdog whose bus had gone spun at 14% each.
        self.start()
        for _ in range(20):
            if session_of(self.sb, b"fake-helper"):
                break
            time.sleep(0.25)
        self.assertTrue(session_of(self.sb, b"fake-helper"), "the fake helper is running")
        subprocess.run(["bash", str(SCRIPT), "stop", str(self.sb)], env=self.env, capture_output=True, timeout=30)
        time.sleep(0.5)
        self.assertEqual(session_of(self.sb), [], "nothing started inside the sandbox survives its stop")


if __name__ == "__main__":
    unittest.main()
