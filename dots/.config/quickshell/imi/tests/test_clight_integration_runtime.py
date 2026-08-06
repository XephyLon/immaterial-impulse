#!/usr/bin/env python3
"""Clight cooperation, against a real shell and a fake busctl.

Clight and services/Brightness.qml both write the same backlight. With the
daemon running, a direct ddcutil/brightnessctl write is silently reverted on
Clight's next recalculation - the shell's brightness changes "jump back". The
fix routes every backlight write through the daemon (IncBl/DecBl over busctl)
whenever it is up, and behaves exactly as before when it is not.

These cases pin both directions of that fork, end to end:

- present: the user's change reaches the daemon and never the direct writers,
  and the daemon's own state (backlight after IncBl, a temperature change it
  makes mid-session, its conf) flows back into the shell. The fake busctl is
  stateful on purpose - GetAll reports a backlight IncBl/DecBl actually
  moved - so convergence is real, not scripted.
- absent, both flavours (no clight binary at all; binary installed but the
  daemon down): stock brightnessctl behaviour, and in the uninstalled case
  not a single busctl spawn (the polling is gated on detection).
- night light stays the shell's: with Clight present, hyprsunset restore
  behaves exactly as test_nightlight_state_runtime.py pins it without Clight.
  That is the recorded conservative decision - a detected daemon must not
  silently change night-light ownership.

Brings its own headless weston, so it needs no display of its own. Skips
when weston or qs is missing, as in CI.
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
HARNESS = ROOT / "ClightIntegrationRuntimeTest.qml"
SOCKET = "wayland-imi-clight-integration"

NIGHT_TEMPERATURE = 4500

RECORD = """#!/usr/bin/env bash
printf '%s\\n' "$(basename "$0") $*" >> "$CLIGHT_EXEC_LOG"
__BODY__
"""

# GetAll answers use --json=short shapes lifted from a real busctl. The
# backlight lives in a state file so IncBl/DecBl actually move what the next
# poll reports; the temperature flips once after a few polls so the harness
# can observe a change the daemon made (as opposed to one it was told about).
BUSCTL_BODY = """\
[ "$CLIGHT_DBUS_UP" = "1" ] || exit 1
state="$CLIGHT_STATE_DIR"
bl=$(cat "$state/bl" 2>/dev/null || echo 0.5)
case "$*" in
  *"GetAll s org.clight.clight.Conf.Backlight")
    printf '{"type":"a{sv}","data":[{"NoAutoCalib":{"type":"b","data":false}}]}\\n'
    ;;
  *"GetAll s org.clight.clight.Conf.Gamma")
    printf '{"type":"a{sv}","data":[{"DayTemp":{"type":"i","data":6500},"NightTemp":{"type":"i","data":4000}}]}\\n'
    ;;
  *"GetAll s org.clight.clight")
    polls=$(( $(cat "$state/polls" 2>/dev/null || echo 0) + 1 ))
    echo "$polls" > "$state/polls"
    temp=4500
    [ "$polls" -gt "${CLIGHT_TEMP_SWITCH_AFTER:-999999}" ] && temp=3500
    printf '{"type":"a{sv}","data":[{"Version":{"type":"s","data":"4.9"},"BlPct":{"type":"d","data":%s},"Temp":{"type":"i","data":%s},"AmbientBr":{"type":"d","data":0.42},"SensorAvail":{"type":"b","data":true},"Inhibited":{"type":"b","data":false}}]}\\n' "$bl" "$temp"
    ;;
  *" IncBl d "*)
    awk -v a="$bl" -v b="${!#}" 'BEGIN{v=a+b; if(v>1)v=1; print v}' > "$state/bl"
    ;;
  *" DecBl d "*)
    awk -v a="$bl" -v b="${!#}" 'BEGIN{v=a-b; if(v<0)v=0; print v}' > "$state/bl"
    ;;
esac
exit 0
"""

BRIGHTNESSCTL_BODY = """\
case "$1" in
  g) echo 128 ;;
  m) echo 255 ;;
esac
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
    return shutil.which("qs") is not None and shutil.which("weston") is not None


@unittest.skipUnless(_runtime_available(), "needs qs and weston on PATH")
class ClightIntegrationRuntimeTest(unittest.TestCase):
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

    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-clight-runtime-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        self.state_home = self.home / "state"
        self.exec_log = self.home / "exec.log"
        self.clight_state = self.home / "clight-state"
        self.clight_state.mkdir()
        self.bin = self.home / "bin"
        self.bin.mkdir(parents=True)

    def fake(self, name, body="exit 0"):
        path = self.bin / name
        path.write_text(RECORD.replace("__BODY__", body))
        path.chmod(0o755)

    def fake_binaries(self, clight_installed):
        self.fake("busctl", BUSCTL_BODY)
        self.fake("brightnessctl", BRIGHTNESSCTL_BODY)
        self.fake("ddcutil", "exit 1")
        # Night-light trio, cold-start flavour (see the nightlight runtime
        # test for why pidof is load-bearing).
        self.fake("hyprsunset")
        self.fake("hyprctl")
        self.fake("pidof", "exit 1")
        if clight_installed:
            self.fake("clight")

    def seed(self):
        shell_config = self.config_home / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        (shell_config / "config.json").write_text(json.dumps({
            "light": {
                "night": {
                    "automatic": False,
                    "colorTemperature": NIGHT_TEMPERATURE,
                },
            },
        }, indent=2))
        states = self.state_home / "quickshell" / "states.json"
        states.parent.mkdir(parents=True)
        states.write_text(json.dumps({
            "night": {"temperatureActive": True},
        }, indent=2))

    def launch(self, installed, available, temp_switch_after=None):
        (self.clight_state / "bl").write_text("0.5\n")
        env = dict(self.env)
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.state_home)
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["PATH"] = f"{self.bin}{os.pathsep}{env['PATH']}"
        env["CLIGHT_EXEC_LOG"] = str(self.exec_log)
        env["CLIGHT_STATE_DIR"] = str(self.clight_state)
        env["CLIGHT_DBUS_UP"] = "1" if available else "0"
        env["CLIGHT_EXPECT_INSTALLED"] = "true" if installed else "false"
        env["CLIGHT_EXPECT_AVAILABLE"] = "true" if available else "false"
        if temp_switch_after is not None:
            env["CLIGHT_TEMP_SWITCH_AFTER"] = str(temp_switch_after)
        proc = subprocess.run(["qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn("[ClightIntegration] failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")
        return output

    def invocations(self):
        if not self.exec_log.exists():
            return []
        return [line for line in self.exec_log.read_text().splitlines() if line.strip()]

    def test_present_defers_backlight_writes_to_the_daemon(self):
        """The bug this proposal exists for: with the daemon up, the user's
        change must reach Clight (which will not revert its own move) and
        never the direct writers it would revert."""
        self.fake_binaries(clight_installed=True)
        self.seed()

        self.launch(installed=True, available=True, temp_switch_after=6)

        calls = self.invocations()
        incbl = [c for c in calls if " org.clight.clight IncBl d " in c]
        decbl = [c for c in calls if " org.clight.clight DecBl d " in c]
        self.assertTrue(incbl, f"the brightness change never reached the daemon: {calls}")
        # The 0.5 -> 0.8 move as the daemon actually received it. The slider
        # animation curve may overshoot, so it is the net that must add up.
        net = (sum(float(c.rsplit(" ", 1)[1]) for c in incbl)
               - sum(float(c.rsplit(" ", 1)[1]) for c in decbl))
        self.assertAlmostEqual(net, 0.3, delta=0.05,
                               msg=f"deltas do not add up to the move: {incbl + decbl}")
        # The startup echo of the initial value is stock behaviour; the acted
        # change specifically must not go through the direct writer.
        self.assertFalse(
            [c for c in calls if c.startswith("brightnessctl --class backlight s 8")],
            f"the change leaked past the daemon into brightnessctl: {calls}")

    def test_present_settings_controls_reach_the_daemon(self):
        self.fake_binaries(clight_installed=True)
        self.seed()

        self.launch(installed=True, available=True, temp_switch_after=6)

        calls = self.invocations()
        self.assertIn("busctl --user set-property org.clight.clight "
                      "/org/clight/clight/Conf/Backlight org.clight.clight.Conf.Backlight "
                      "NoAutoCalib b true", calls,
                      f"disabling auto calibration never reached the daemon: {calls}")
        self.assertIn("busctl --user set-property org.clight.clight "
                      "/org/clight/clight/Conf/Gamma org.clight.clight.Conf.Gamma "
                      "DayTemp i 6000", calls,
                      f"the day temperature write never reached the daemon: {calls}")

    def test_present_leaves_night_light_ownership_with_the_shell(self):
        """The conservative decision, observed: with Clight up, hyprsunset
        restore behaves exactly as the nightlight runtime test pins it
        without Clight - a warm cold-start launch, no identity launch."""
        self.fake_binaries(clight_installed=True)
        self.seed()

        self.launch(installed=True, available=True, temp_switch_after=6)

        calls = self.invocations()
        self.assertIn(f"hyprsunset --temperature {NIGHT_TEMPERATURE}", calls,
                      f"night light restore changed under Clight: {calls}")
        self.assertNotIn("hyprsunset --identity", calls)

    def test_not_installed_degrades_to_stock_behaviour(self):
        """No clight binary: the stock writer runs, and detection gating
        means not one busctl is ever spawned."""
        self.fake_binaries(clight_installed=False)
        self.seed()

        self.launch(installed=False, available=False)

        calls = self.invocations()
        self.assertIn("brightnessctl --class backlight s 80% --quiet", calls,
                      f"stock backlight write missing: {calls}")
        self.assertFalse([c for c in calls if c.startswith("busctl ")],
                         f"a machine without clight spawned busctl: {calls}")

    def test_daemon_down_degrades_to_stock_behaviour(self):
        """clight installed but not running: polls fail, the shell degrades
        to writing the backlight itself."""
        self.fake_binaries(clight_installed=True)
        self.seed()

        self.launch(installed=True, available=False)

        calls = self.invocations()
        self.assertIn("brightnessctl --class backlight s 80% --quiet", calls,
                      f"stock backlight write missing with the daemon down: {calls}")
        self.assertFalse([c for c in calls if " IncBl d " in c or " DecBl d " in c],
                         f"commands were sent to a daemon that is not there: {calls}")


if __name__ == "__main__":
    unittest.main()
