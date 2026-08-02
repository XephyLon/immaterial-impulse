#!/usr/bin/env python3
"""Night light on/off state, against a real shell and a fake hyprsunset.

hyprsunset has no state query. On 0.4.0 `hyprctl hyprsunset --help` lists three
requests - `temperature`, `gamma`, `identity` - and the daemon socket answers
"invalid command" to `state`, `status`, `info`, `enabled`, `active`, `matrix`.
The bare `temperature` request reports the last temperature the daemon was
*told*; `identity`, the off switch, never resets it. Measured: a daemon running
as `hyprsunset --identity` (neutral screen) reports 6000, and a daemon put into
identity after `temperature 5000` still reports 5000.

`services/Hyprsunset.qml` used to infer on/off from that query by comparing it
against a hardcoded `"6500"` - the *slider's* neutral end in NightLightDialog,
not anything hyprsunset knows about - so `temperatureActive` was true whenever
the last-set temperature was not literally 6500, including with the identity
matrix applied and the screen perfectly neutral. The indicator and the toggle
could then disagree with the display.

So the state is the shell's, persisted in states.json and re-applied at startup.
These cases pin both halves: what the shell comes up believing, and what it
actually tells the daemon to do about it.

Fake `hyprsunset`, `hyprctl` and `pidof` executables go at the front of PATH and
record their argv. `pidof` is the load-bearing one: `startHyprsunset` runs
`pidof hyprsunset || hyprsunset ...`, so on any machine with a live daemon the
launch path is skipped entirely and an assertion about launch flags passes
without ever running. Faking it makes cold start and warm start both reachable,
on purpose, in the same suite.

Brings its own headless weston, so it needs no display of its own. Skips when
weston or qs is missing, as in CI.
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
HARNESS = ROOT / "NightLightStateRuntimeTest.qml"
SOCKET = "wayland-imi-nightlight-state"

# Deliberately not 6500 and not 6000: the removed sentinel and hyprsunset's own
# default are exactly the two numbers that could make a broken check look right.
NIGHT_TEMPERATURE = 4500

FAKE = """#!/usr/bin/env bash
printf '%s\\n' "$(basename "$0") $*" >> "$NIGHTLIGHT_EXEC_LOG"
__BODY__
"""


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
class NightLightStateRuntimeTest(unittest.TestCase):
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

        # This box's headless EGL has no driver, so force software rendering.
        cls.env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        cls.env["QT_QUICK_BACKEND"] = "software"

    @classmethod
    def tearDownClass(cls):
        _stop(cls.weston)

    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-nightlight-runtime-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        self.state_home = self.home / "state"
        self.states = self.state_home / "quickshell" / "states.json"
        self.exec_log = self.home / "exec.log"
        self.bin = self.home / "bin"
        self.bin.mkdir(parents=True)

    def fake_binaries(self, daemon_running):
        """`hyprsunset`, `hyprctl` and `pidof` that only record what they were
        asked to do. `pidof` decides which branch of `pidof hyprsunset || ...`
        the shell takes, i.e. cold start versus a daemon that is already up."""
        bodies = {
            "hyprsunset": "exit 0",
            "hyprctl": "exit 0",
            # Real `pidof` prints nothing and exits 1 when the process is absent.
            "pidof": 'printf "4242\\n"; exit 0' if daemon_running else "exit 1",
        }
        for name, body in bodies.items():
            path = self.bin / name
            path.write_text(FAKE.replace("__BODY__", body))
            path.chmod(0o755)

    def seed(self, temperature_active, automatic=False):
        shell_config = self.config_home / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        (shell_config / "config.json").write_text(json.dumps({
            "light": {
                "night": {
                    "automatic": automatic,
                    "colorTemperature": NIGHT_TEMPERATURE,
                },
            },
        }, indent=2))
        self.states.parent.mkdir(parents=True)
        self.states.write_text(json.dumps({
            "night": {"temperatureActive": temperature_active},
        }, indent=2))

    def launch(self, expect_active, toggle=""):
        env = dict(self.env)
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.state_home)
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["PATH"] = f"{self.bin}{os.pathsep}{env['PATH']}"
        env["NIGHTLIGHT_EXEC_LOG"] = str(self.exec_log)
        env["NIGHTLIGHT_EXPECT_ACTIVE"] = "true" if expect_active else "false"
        env["NIGHTLIGHT_TOGGLE"] = toggle
        proc = subprocess.run(["qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn("[NightLightState] failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")
        return output

    def invocations(self):
        if not self.exec_log.exists():
            return []
        return [line for line in self.exec_log.read_text().splitlines() if line.strip()]

    def stored_state(self):
        return json.loads(self.states.read_text())["night"]["temperatureActive"]

    def assert_never_queried(self):
        """The whole point. A bare `hyprctl hyprsunset temperature` is a
        question hyprsunset cannot answer, so the shell must not be asking it."""
        self.assertNotIn("hyprctl hyprsunset temperature", self.invocations(),
                         "the shell is still inferring state from the useless query")

    def test_off_stays_off_and_the_daemon_is_launched_neutral(self):
        """Nothing on screen, nothing claimed. A cold start must bring the
        daemon up with `--identity`: launched bare it applies its own 6000K
        default, which is a warm tint, not a no-op."""
        self.fake_binaries(daemon_running=False)
        self.seed(temperature_active=False)

        self.launch(expect_active=False)

        calls = self.invocations()
        self.assertIn("hyprsunset --identity", calls, f"no neutral launch in {calls}")
        self.assertFalse([c for c in calls if "--temperature" in c],
                         f"night light was off, nothing may set a temperature: {calls}")
        self.assert_never_queried()

    def test_on_is_restored_and_re_applied_to_a_cold_daemon(self):
        """The case the old query got wrong in the other direction, and the
        reason restoring has to *apply*: after a reboot the daemon is gone, so
        believing "on" without telling the new daemon leaves a neutral screen
        under an indicator that says night light is active."""
        self.fake_binaries(daemon_running=False)
        self.seed(temperature_active=True)

        self.launch(expect_active=True)

        calls = self.invocations()
        self.assertIn(f"hyprsunset --temperature {NIGHT_TEMPERATURE}", calls,
                      f"no warm launch in {calls}")
        self.assertNotIn("hyprsunset --identity", calls,
                         f"night light was on, it must not be launched neutral: {calls}")
        self.assert_never_queried()

    def test_a_daemon_that_is_already_up_is_corrected_over_hyprctl(self):
        """`startHyprsunset` short-circuits on `pidof hyprsunset ||`, so launch
        flags reach nothing when a daemon is already running - the hyprctl call
        is what actually applies the state in that case, and it has to be sent."""
        self.fake_binaries(daemon_running=True)
        self.seed(temperature_active=True)

        self.launch(expect_active=True)

        calls = self.invocations()
        self.assertIn(f"hyprctl hyprsunset temperature {NIGHT_TEMPERATURE}", calls,
                      f"a running daemon was never told the temperature: {calls}")
        self.assertFalse([c for c in calls if c.startswith("hyprsunset ")],
                         f"the daemon was already up, it must not be relaunched: {calls}")
        self.assert_never_queried()

    def test_turning_it_off_reaches_the_daemon_and_the_state_file(self):
        """A toggle the next launch has to be able to read back. This is the
        one that used to look fine and wasn't: identity did turn the screen
        neutral, but nothing recorded it, and the next startup's query saw the
        stale non-6500 number and reported active."""
        self.fake_binaries(daemon_running=True)
        self.seed(temperature_active=True)

        self.launch(expect_active=True, toggle="off")

        self.assertIn("hyprctl hyprsunset identity", self.invocations())
        self.assertFalse(self.stored_state(), "the off state never reached states.json")

    def test_turning_it_on_reaches_the_daemon_and_the_state_file(self):
        self.fake_binaries(daemon_running=True)
        self.seed(temperature_active=False)

        self.launch(expect_active=False, toggle="on")

        self.assertIn(f"hyprctl hyprsunset temperature {NIGHT_TEMPERATURE}",
                      self.invocations())
        self.assertTrue(self.stored_state(), "the on state never reached states.json")


if __name__ == "__main__":
    unittest.main()
