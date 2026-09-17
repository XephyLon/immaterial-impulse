#!/usr/bin/env python3
"""The review sandbox's stop leaves nothing of the sandbox behind, and nothing else.

`tests/sandbox/sandbox_shell.sh stop` killed the pid it had recorded for the
shell, and that pid was the background SUBSHELL of `cd "$ROOT" && qs ... &`,
not the shell; nor did it end anything the shell had started. Shells and their
helpers piled up across review sandboxes, spun, and a review round's CPU
readings measured them instead of the build. The script is driven here against
fake `Hyprland`, `dbus-run-session` and `qs` binaries, so the check runs
anywhere and never touches a compositor.
"""
import os
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tests" / "sandbox" / "sandbox_shell.sh"
MARKER = "IMI_SANDBOX_SESSION"

FAKE_HYPRLAND = """#!/usr/bin/env python3
import os, socket, time
if os.environ.get("FAKE_HYPR_NEVER_UP"):
    time.sleep(600)
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
# The shell: argv[0] a full path ending in quickshell, as the real launcher's
# exec leaves it; starts a detached helper of its own, as the real shell does;
# deaf to SIGTERM when the test asks (a shell stuck in teardown).
FAKE_QS = """#!/usr/bin/env bash
setsid -f bash -c 'exec -a fake-helper sleep 600'
if [ -n "${FAKE_QS_DEAF:-}" ]; then
  exec -a /opt/fake/build/src/quickshell python3 -c 'import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(600)'
fi
exec -a /opt/fake/build/src/quickshell sleep 600
"""


def argv0(pid):
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")[0].decode(errors="replace")
    except OSError:
        return ""


def session_of(sb, name=None):
    """Every process carrying the sandbox's marker; with `name`, only those
    whose argv[0] basename is it."""
    want = f"{MARKER}={sb}".encode()
    found = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            env = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        except OSError:
            continue
        if want not in env:
            continue
        if name is not None and os.path.basename(argv0(pid)) != name:
            continue
        found.append(int(pid))
    return found


def shells_of(sb):
    return session_of(sb, "quickshell")


class SandboxStopTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="imi-sbt-")
        t = Path(self.tmp.name)
        self.bin = t / "bin"; self.bin.mkdir()
        # Files on PATH, keyed by name: nothing here launches a shell - the
        # script under test does, and what it finds is the fake.
        fakes = {"Hyprland": FAKE_HYPRLAND, "dbus-run-session": FAKE_DBUS, "qs": FAKE_QS}
        for name, body in fakes.items():
            p = self.bin / name; p.write_text(body); p.chmod(0o755)
        self.root = t / "shell"; (self.root / "defaults").mkdir(parents=True)
        (self.root / "defaults" / "config.json").write_text("{}")
        self.sb = t / "sb"
        self.parent_run = t / "parent"; self.parent_run.mkdir(mode=0o700)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        XDG_RUNTIME_DIR=str(self.parent_run), WAYLAND_DISPLAY="wayland-parent")
        self.env.pop(MARKER, None)
        self.strays = []
        self.run_dirs = set()

    def tearDown(self):
        for pid in session_of(self.sb):
            os.kill(pid, signal.SIGKILL)
        for p in self.strays:
            p.kill(); p.wait()
        self.stop()
        self.tmp.cleanup()
        # Only the run dirs this test's own starts made: a review sandbox
        # started meanwhile has its own, and it is none of this test's business.
        leaked = {d for d in self.run_dirs if os.path.exists(d)}
        for d in leaked:
            subprocess.run(["rm", "-rf", d])
        self.assertEqual(leaked, set(), "a test left a sandbox run dir in /tmp")

    def run_script(self, *args, env=None):
        return subprocess.run(["bash", str(SCRIPT), *args], env=env or self.env,
                              capture_output=True, text=True, timeout=60)

    def stop(self, env=None):
        return self.run_script("stop", str(self.sb), env=env)

    def remember_run_dir(self):
        try:
            self.run_dirs.add((self.sb / "run.path").read_text().strip())
        except OSError:
            pass

    def start(self, env=None):
        r = self.run_script("start", str(self.root), str(self.sb), env=env)
        self.remember_run_dir()
        self.assertIn("sandbox up", r.stdout, r.stdout + r.stderr)
        for _ in range(40):
            if shells_of(self.sb) and session_of(self.sb, "fake-helper"):
                break
            time.sleep(0.25)
        return r

    def marked(self, *argv):
        """A process that belongs to the sandbox without the script having started it."""
        env = dict(self.env, **{MARKER: str(self.sb)})
        p = subprocess.Popen(list(argv), env=env)
        self.strays.append(p)
        return p

    def recorded_pid(self):
        for line in (self.sb / "env").read_text().splitlines():
            if "SANDBOX_QS_PID=" in line:
                return int(line.split("SANDBOX_QS_PID=")[1])
        self.fail("no SANDBOX_QS_PID in the env file")

    def test_the_recorded_pid_is_the_shell(self):
        self.start()
        self.assertEqual(shells_of(self.sb), [self.recorded_pid()],
                         "the env file names the shell process, not a subshell around it")

    def test_stop_ends_the_whole_session_and_says_so(self):
        # The shell starts helpers of its own (tray watchdog, monitors, a
        # keyring, a D-Bus): they outlived every stop, 274 of them after a
        # day of reviews, and a watchdog whose bus had gone spun at 14% each.
        self.start()
        self.assertTrue(shells_of(self.sb))
        self.assertTrue(session_of(self.sb, "fake-helper"), "the fake helper is running")
        r = self.stop()
        self.assertRegex(r.stdout, r"sandbox stopped: \d+ processes? ended, nothing left")
        time.sleep(0.3)
        self.assertEqual(session_of(self.sb), [], "nothing started inside the sandbox survives its stop")

    def test_a_shell_deaf_to_sigterm_is_still_killed(self):
        self.start(env=dict(self.env, FAKE_QS_DEAF="1"))
        r = self.stop()
        self.assertRegex(r.stdout, r"sandbox stopped: \d+ processes ended, nothing left \(1 needed SIGKILL\)")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(shells_of(self.sb), [])

    def test_the_sandbox_is_the_same_however_its_path_is_spelled(self):
        # The marker is the sandbox dir; a start given one spelling and a stop
        # given another (relative, trailing slash) found nothing and reported
        # "nothing left" over a running session.
        self.start()
        rel = os.path.relpath(self.sb, self.tmp.name) + "/"
        r = subprocess.run(["bash", str(SCRIPT), "stop", rel], env=self.env, cwd=self.tmp.name,
                           capture_output=True, text=True, timeout=60)
        self.assertRegex(r.stdout, r"sandbox stopped: [1-9]\d* processes ended")
        self.assertEqual(session_of(self.sb), [])

    def test_a_sandbox_path_is_matched_literally(self):
        # The marker scan must not read the path as a pattern: a sibling
        # whose name the pattern "sb." would match is not this sandbox.
        other = Path(self.tmp.name) / "sbX"
        env = dict(self.env, **{MARKER: str(other)})
        p = subprocess.Popen(["sleep", "600"], env=env); self.strays.append(p)
        dotted = Path(self.tmp.name) / "sb."
        r = subprocess.run(["bash", str(SCRIPT), "stop", str(dotted)], env=self.env,
                           capture_output=True, text=True, timeout=60)
        self.assertIn("sandbox stopped: 0 processes ended", r.stdout)
        self.assertIsNone(p.poll(), "a sandbox whose path the other's matches as a pattern is left alone")

    def test_start_refuses_to_wipe_a_directory_that_is_not_a_sandbox(self):
        # Including one that happens to hold files a sandbox also has - a
        # Python venv is commonly named env/.
        self.sb.mkdir(parents=True)
        (self.sb / "precious").write_text("x")
        (self.sb / "env").mkdir()
        (self.sb / "run.path").write_text("/tmp/imi-sb-abcdef\n")
        r = self.run_script("start", str(self.root), str(self.sb))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("not a sandbox", r.stderr)
        self.assertIn("stop", r.stderr, "the refusal says what to do if it is an old sandbox")
        self.assertTrue((self.sb / "precious").exists())

    def test_a_start_that_fails_ends_the_session_it_began(self):
        # The compositor never comes up: start reports the failure, and the
        # session it launched (the compositor, the D-Bus wrapper) is gone.
        env = dict(self.env, FAKE_HYPR_NEVER_UP="1", SANDBOX_START_WAIT="2")
        r = self.run_script("start", str(self.root), str(self.sb), env=env)
        self.remember_run_dir()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("FAILED", r.stdout)
        self.assertIn("SANDBOX_START_WAIT", r.stderr, "the test hook announces itself")
        time.sleep(0.3)
        self.assertEqual(session_of(self.sb), [], "nothing of the failed start is left running")
        for d in self.run_dirs:
            self.assertFalse(os.path.exists(d), "the failed start removed its own run dir")

    def test_the_start_wait_hook_takes_only_a_whole_number_of_seconds(self):
        for bad in ("abc", "0", "a[$(touch /tmp/x)]"):
            r = self.run_script("start", str(self.root), str(self.sb), env=dict(self.env, SANDBOX_START_WAIT=bad))
            self.assertEqual(r.returncode, 2, bad)
            self.assertFalse(self.sb.exists(), f"{bad!r} started nothing")

    def test_the_test_only_kill_override_announces_itself(self):
        self.sb.mkdir(parents=True)
        r = self.run_script("stop", str(self.sb), env=dict(self.env, SANDBOX_STOP_KILL="true"))
        self.assertIn("SANDBOX_STOP_KILL", r.stderr)
        r = self.run_script("stop", str(self.sb), env=dict(self.env, SANDBOX_STOP_KILL="rm -rf /nonexistent"))
        self.assertNotEqual(r.returncode, 0, "only the test's no-op is accepted")

    def test_start_does_not_wipe_a_sandbox_it_could_not_stop(self):
        # A stop that refuses (run from inside a sandbox) must stop the start
        # too, or the wipe orphans the very session the refusal protected.
        self.start()
        env = dict(self.env, **{MARKER: "/elsewhere"})
        r = self.run_script("start", str(self.root), str(self.sb), env=env)
        self.assertNotEqual(r.returncode, 0)
        self.assertTrue((self.sb / "env").exists(), "the running sandbox's dir is intact")
        self.assertTrue(shells_of(self.sb))

    def test_an_incomplete_stop_says_so_and_fails(self):
        # A marked process stop could not end is reported, and the exit
        # status says so, so a script can tell. The kill is made to do
        # nothing through the script's test-only override.
        self.sb.mkdir(parents=True)
        self.marked("sleep", "600")
        r = self.run_script("stop", str(self.sb), env=dict(self.env, SANDBOX_STOP_KILL="true"))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("STILL RUNNING", r.stderr)
        self.assertIn("incomplete", r.stdout)

    def test_stop_spares_a_terminal_that_sourced_the_env_file(self):
        # The README's workflow sources <sandbox>/env, which exports the
        # sandbox's XDG_CONFIG_HOME into the caller - and a stop matching on
        # that variable killed its own caller.
        self.start()
        caller = subprocess.Popen(["bash", "-c", f'source "{self.sb}/env"; exec -a sourced-terminal sleep 600'], env=self.env)
        self.strays.append(caller)
        time.sleep(0.3)
        r = self.run_script("stop", str(self.sb), env=dict(self.env, BASH_ENV=f"{self.sb}/env"))
        self.assertIn("sandbox stopped", r.stdout)
        self.assertIsNone(caller.poll(), "a terminal that sourced the env file is not part of the sandbox")
        self.assertEqual(shells_of(self.sb), [])

    def test_stop_never_kills_a_stranger_behind_a_stale_pid(self):
        # An env file outlives its session (a crash, a reboot); the pids in it
        # can belong to anything by then.
        stranger = subprocess.Popen(["sleep", "600"])
        self.strays.append(stranger)
        self.sb.mkdir(parents=True)
        (self.sb / "env").write_text(
            f"export XDG_CONFIG_HOME={self.sb}/config\n"
            f"export SANDBOX_HYPR_PID={stranger.pid}\n"
            f"export SANDBOX_QS_PID={stranger.pid}\n")
        r = self.stop()
        self.assertIn("sandbox stopped", r.stdout)
        self.assertIsNone(stranger.poll(), "a process that reused a recorded pid is left alone")

    def test_stop_reaches_a_session_whose_start_never_wrote_an_env_file(self):
        # A start that fails before the env file exists still leaves its
        # compositor running; the marker is all stop needs.
        self.sb.mkdir(parents=True)
        (self.sb / ".imi-sandbox").write_text("x")
        leftover = self.marked("sleep", "600")
        r = self.stop()
        self.assertIn("sandbox stopped", r.stdout)
        leftover.wait(timeout=10)
        self.assertEqual(session_of(self.sb), [])

    def test_stop_removes_only_a_run_dir_it_made(self):
        # run.path feeds an unmount pass and an rm -rf: anything that is not
        # one of start's own /tmp/imi-sb-XXXXXX dirs is left alone.
        keep = Path(self.tmp.name) / "not-a-run-dir"; keep.mkdir()
        (keep / "file").write_text("x")
        self.sb.mkdir(parents=True)
        for bogus in (str(keep), "", "/", "/tmp/imi-sb-../etc"):
            (self.sb / "run.path").write_text(bogus + "\n")
            r = self.stop()
            self.assertIn("sandbox stopped", r.stdout, bogus)
            self.assertTrue((keep / "file").exists(), f"run.path {bogus!r} removed a directory start never made")

    def test_start_over_a_live_sandbox_stops_it_first(self):
        # Reusing a sandbox dir used to wipe it with its session still
        # running - which then nothing could find by its env file.
        self.start()
        old = shells_of(self.sb)
        old_run = (self.sb / "run.path").read_text().strip()
        self.start()
        time.sleep(0.3)
        now = shells_of(self.sb)
        self.assertEqual(len(now), 1, now)
        self.assertNotEqual(now, old, "the old shell was stopped, a new one started")
        self.assertFalse(os.path.exists(old_run), "the old session's run dir went with it")

    def test_stop_refuses_to_run_from_inside_the_sandbox(self):
        # Anything started inside the sandbox carries its marker, so a stop
        # run from there would end its own caller half way through.
        self.start()
        r = self.stop(env=dict(self.env, **{MARKER: str(self.sb)}))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("inside", r.stderr + r.stdout)
        self.assertTrue(shells_of(self.sb), "nothing was stopped")


if __name__ == "__main__":
    unittest.main()
