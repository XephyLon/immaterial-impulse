#!/usr/bin/env python3
"""The phone-connect stream's process lifetime, against a real shell and a fake busctl.

The parsing half of `busctl monitor` is covered by the QML suite through the
logic-only double. The LIFETIME is not reachable from there at all -
qmltestrunner cannot construct a Quickshell `Process` - and it is the half
CONTRIBUTING.md names outright: an instant-exit streaming command kept alive
by a `running` binding is a tight respawn loop that starves Quickshell.

So this drives the real singleton in a real `qs` with a fake `busctl` on PATH
and reads the spawns back:

- stream: the monitor comes up for KDE Connect, and a battery change reaches
  the shell from a SIGNAL. That is an oracle rather than an observation
  because the poll interval is seeded at ten minutes for this case - the
  timer cannot deliver the new charge inside the run, so a stream that never
  worked reports the pre-signal value and reddens. (Seeded through
  `config.json` rather than assigned in the harness: the stored value is the
  one the JsonAdapter merges over the QML default, so it is also the one that
  runs.)
- crash: a `busctl monitor` that exits immediately. The retries are counted
  and the GAPS between them measured, because "it stopped after six spawns"
  is satisfied by six spawns in six milliseconds - which is the bug. The
  model must still be populated afterwards, since giving up means falling
  back to the poll rather than going dark.
- valent: not one monitor spawn. Its signal set could not be verified
  against a live daemon, and a stream that only works for one backend is a
  regression in the other.
- none: no daemon, so nothing streams and nothing is spawned for it.

Brings its own headless weston and its own session bus (`dbus-run-session`,
never the developer's - see lint_runtime_bus_isolation.py). Skips when
weston, qs or dbus-run-session are missing, as in CI.
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "PhoneConnectMonitorRuntimeTest.qml"
SOCKET = "wayland-imi-phoneconnect-monitor"

DEVICE_ID = "6131a746_571a_4176_a007_95625ff8e08e"
CHARGE_BEFORE = 41
CHARGE_AFTER = 87

# The service's own declared ceiling. Read out of the source rather than
# copied: a check that carries its own copy of the number passes when the
# service's changes underneath it.
CEILING = int(re.search(
    r"readonly property int monitorAttemptCeiling:\s*(\d+)",
    (ROOT / "services" / "PhoneConnect.qml").read_text()).group(1))

# 1s, 2s, 4s, ... capped at 30s - monitorBackoffDelay, which the QML suite
# pins as arithmetic. Here it is what the gaps between spawns must look like.
EXPECTED_DELAYS = [min(30, 2 ** n) for n in range(CEILING)]

RECORD = """#!/usr/bin/env bash
printf '%s %s\\n' "$(date +%s.%N)" "$*" >> "$PHONE_EXEC_LOG"
__BODY__
"""

# --json=short shapes lifted from a real busctl against a live KDE Connect
# daemon. The battery charge comes out of a state file that the monitor verb
# rewrites, so a poll after the signal reports something a poll before it
# could not have.
BUSCTL_BODY = """\
state="$PHONE_STATE_DIR"
charge=$(cat "$state/charge" 2>/dev/null || echo %(before)s)
case "$*" in
  *"org.freedesktop.DBus ListNames")
    case "$PHONE_FAKE_BACKEND" in
      kdeconnect) printf '{"type":"as","data":[[":1.5","org.freedesktop.DBus","org.kde.kdeconnect.daemon"]]}\\n' ;;
      valent)     printf '{"type":"as","data":[[":1.5","org.freedesktop.DBus","ca.andyholmes.Valent"]]}\\n' ;;
      *)          printf '{"type":"as","data":[[":1.5","org.freedesktop.DBus"]]}\\n' ;;
    esac
    ;;
  *"org.kde.kdeconnect.daemon devices bb false false")
    printf '{"type":"as","data":[["%(device)s"]]}\\n'
    ;;
  *"GetAll s org.kde.kdeconnect.device.battery")
    printf '{"type":"a{sv}","data":[{"charge":{"type":"i","data":%%s},"isCharging":{"type":"b","data":false}}]}\\n' "$charge"
    ;;
  *"GetAll s org.kde.kdeconnect.device")
    printf '{"type":"a{sv}","data":[{"name":{"type":"s","data":"Galaxy S23 Ultra"},"type":{"type":"s","data":"phone"},"isPaired":{"type":"b","data":true},"isReachable":{"type":"b","data":true}}]}\\n'
    ;;
  *"GetManagedObjects")
    printf '{"type":"a{oa{sa{sv}}}","data":[{"/ca/andyholmes/Valent/Device/0":{"ca.andyholmes.Valent.Device":{"Id":{"type":"s","data":"abc123"},"Name":{"type":"s","data":"Pixel 9"},"Type":{"type":"s","data":"phone"},"State":{"type":"u","data":3}}}}]}\\n'
    ;;
  *"org.gtk.Actions DescribeAll")
    printf '{"type":"a{s(bgav)}","data":[{"battery.state":[true,"",[{"type":"a{sv}","data":{"charging":{"type":"b","data":false},"percentage":{"type":"d","data":%(before)s.0},"is-present":{"type":"b","data":true}}}]]}]}\\n'
    ;;
  *monitor*)
    case "$PHONE_FAKE_MONITOR" in
      crash)
        # busctl's own answer to a match rule the bus rejects, which is the
        # instant-exit case the backoff exists for.
        echo "Call to org.freedesktop.DBus.Monitoring.BecomeMonitor failed: Invalid match rule" >&2
        exit 1
        ;;
      stream)
        sleep 1
        echo %(after)s > "$state/charge"
        printf '{"type":"signal","endian":"l","flags":1,"version":1,"cookie":325,"timestamp-realtime":1787149977815500,"sender":":1.55","path":"/modules/kdeconnect/devices/%(device)s/battery","interface":"org.kde.kdeconnect.device.battery","member":"refreshed","payload":{"type":"bi","data":[false,%(after)s]}}\\n'
        sleep 3600
        ;;
    esac
    ;;
esac
exit 0
""" % {"device": DEVICE_ID, "before": CHARGE_BEFORE, "after": CHARGE_AFTER}


# How many checks the harness runs, per shape it is launched in. Literals
# rather than anything read back out of the harness's own output: a harness
# whose step list shrinks must redden here instead of reporting
# `failures: 0` for a shorter run.
EXPECTED_CHECKS_STREAMING = 5
EXPECTED_CHECKS_GAVE_UP = 6
EXPECTED_CHECKS_NO_DAEMON = 3


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def _runtime_available():
    return all(shutil.which(name) for name in ("qs", "weston", "dbus-run-session"))


@unittest.skipUnless(_runtime_available(), "needs qs, weston and dbus-run-session on PATH")
class PhoneConnectMonitorRuntimeTest(unittest.TestCase):
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
        self.home = Path(tempfile.mkdtemp(prefix="imi-phoneconnect-runtime-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        self.exec_log = self.home / "exec.log"
        self.state = self.home / "phone-state"
        self.state.mkdir()
        (self.state / "charge").write_text(f"{CHARGE_BEFORE}\n")
        self.bin = self.home / "bin"
        self.bin.mkdir(parents=True)
        self.fake("busctl", BUSCTL_BODY)

    def fake(self, name, body="exit 0"):
        path = self.bin / name
        path.write_text(RECORD.replace("__BODY__", body))
        path.chmod(0o755)

    def seed(self, poll_ms):
        shell_config = self.config_home / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        (shell_config / "config.json").write_text(json.dumps({
            "networking": {"phoneConnect": {"enable": True, "pollInterval": poll_ms}},
        }, indent=2))

    def launch(self, *, backend, monitor_mode, expect_monitor, expect_charge,
               checks, poll_ms, settle_ms):
        self.seed(poll_ms)
        env = dict(self.env)
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["PATH"] = f"{self.bin}{os.pathsep}{env['PATH']}"
        env["PHONE_EXEC_LOG"] = str(self.exec_log)
        env["PHONE_STATE_DIR"] = str(self.state)
        env["PHONE_FAKE_BACKEND"] = backend
        env["PHONE_FAKE_MONITOR"] = monitor_mode
        env["PHONE_EXPECT_BACKEND"] = backend
        env["PHONE_EXPECT_MONITOR"] = expect_monitor
        env["PHONE_EXPECT_CHARGE"] = str(expect_charge)
        env["PHONE_SETTLE_MS"] = str(settle_ms)
        # dbus-run-session, not the inherited DBUS_SESSION_BUS_ADDRESS: this
        # harness must see the services it declares and no others.
        proc = subprocess.run(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=300)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[PhoneConnectMonitor] checks: {checks} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")
        return output

    def invocations(self):
        if not self.exec_log.exists():
            return []
        out = []
        for line in self.exec_log.read_text().splitlines():
            if not line.strip():
                continue
            stamp, _, argv = line.partition(" ")
            out.append((float(stamp), argv))
        return out

    def monitor_spawns(self):
        return [entry for entry in self.invocations() if " monitor " in f" {entry[1]} "]

    def test_a_signal_delivers_a_change_the_poll_could_not_have(self):
        """The point of the slice. The poll is ten minutes out, so the new
        charge can only have come from the monitor's signal."""
        output = self.launch(backend="kdeconnect", monitor_mode="stream",
                             expect_monitor="running", expect_charge=CHARGE_AFTER,
                             checks=EXPECTED_CHECKS_STREAMING,
                             poll_ms=600000, settle_ms=8000)
        self.assertIn("[PhoneConnectMonitor] service constructed", output)

        spawns = self.monitor_spawns()
        self.assertEqual(len(spawns), 1, f"expected one monitor spawn, got {spawns}")
        argv = spawns[0][1]
        self.assertIn("--json=short", argv)
        self.assertIn("--match=type='signal',sender='org.kde.kdeconnect.daemon'", argv)
        self.assertIn("path_namespace='/modules/kdeconnect'", argv)

        # Exactly one sweep per reason: the startup poll, then the one the
        # signal asked for. A stream that re-swept per burst line, or a
        # settle that fired while a sweep was in flight, would show more.
        list_names = [entry for entry in self.invocations() if entry[1].endswith("ListNames")]
        self.assertEqual(len(list_names), 2,
                         f"expected a startup sweep and a signal-driven one, got {list_names}")

    def test_an_instantly_exiting_monitor_is_backed_off_and_given_up_on(self):
        """The shape CONTRIBUTING.md forbids answering with a `running`
        binding. Both halves are asserted, because "it stopped after N
        spawns" is satisfied by N spawns in N milliseconds - which is the
        starvation bug itself."""
        settle = int((sum(EXPECTED_DELAYS) + 10) * 1000)
        self.launch(backend="kdeconnect", monitor_mode="crash",
                    expect_monitor="failed", expect_charge=CHARGE_BEFORE,
                    checks=EXPECTED_CHECKS_GAVE_UP,
                    poll_ms=2000, settle_ms=settle)

        spawns = self.monitor_spawns()
        self.assertEqual(len(spawns), CEILING + 1,
                         f"expected the first spawn plus {CEILING} retries, got {len(spawns)}")
        gaps = [round(b[0] - a[0], 1) for a, b in zip(spawns, spawns[1:])]
        self.assertEqual(len(gaps), len(EXPECTED_DELAYS))
        for gap, expected in zip(gaps, EXPECTED_DELAYS):
            self.assertGreaterEqual(
                gap, expected * 0.8,
                f"restart {gaps.index(gap) + 1} came back after {gap}s, not {expected}s: {gaps}")

    def test_valent_is_never_streamed_because_its_signals_are_unverified(self):
        self.launch(backend="valent", monitor_mode="crash",
                    expect_monitor="idle", expect_charge=CHARGE_BEFORE,
                    checks=EXPECTED_CHECKS_STREAMING,
                    poll_ms=2000, settle_ms=6000)
        self.assertEqual(self.monitor_spawns(), [],
                         "a monitor was spawned for a backend with no verified signal set")

    def test_no_daemon_spawns_no_monitor(self):
        self.launch(backend="none", monitor_mode="crash",
                    expect_monitor="idle", expect_charge=-1,
                    checks=EXPECTED_CHECKS_NO_DAEMON,
                    poll_ms=2000, settle_ms=6000)
        self.assertEqual(self.monitor_spawns(), [],
                         "a machine with no phone daemon spawned a monitor")


if __name__ == "__main__":
    unittest.main()
