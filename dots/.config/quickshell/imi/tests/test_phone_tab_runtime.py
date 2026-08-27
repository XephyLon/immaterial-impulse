#!/usr/bin/env python3
"""The Phone tab, driven against a fake daemon in a real shell.

`PhoneTabRuntimeTest.qml` builds the real Phone tab over the real
`services/PhoneConnect.qml`, with a fake `busctl` on PATH exposing two
devices: a paired, reachable phone (battery, address, LTE report) and an
unpaired laptop whose pairState says the peer asked. The harness reads the
surface back - the chip, the pills in their priority order, one row of six
actions and which of them answer, the two navigation cards, the sub-page
overlay degrading to nothing while the other workstream's pages are absent,
the notification list owning the leftover height (measured: take the pairing
card away and the list grows by exactly that card), the pairing card and the
roster behind the chip's arrow - and clicks Accept and Decline.

Those two clicks are scored HERE, off the fake's recorded invocations:
`acceptPairing` and `cancelPairing` must each have been called once, on the
laptop's device path, and never on the phone's. A click that reached nothing
would leave the harness green (a button is a button) and this red.

Brings its own headless weston and its own session bus (`dbus-run-session`).
Skips when weston, qs or dbus-run-session are missing, as in CI.
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
HARNESS = ROOT / "PhoneTabRuntimeTest.qml"
SOCKET = "wayland-imi-phone-tab"

PHONE_ID = "6131a746_571a_4176_a007_95625ff8e08e"
LAPTOP_ID = "3b767a2479954eceaf9f1e7fa212f48e"
PHONE_ADDRESS = "192.168.100.179"
LAPTOP_ADDRESS = "192.168.100.99"

# A literal, never read back out of the harness's own output: a step list
# that shrinks must redden here instead of reporting `failures: 0` for a
# shorter run.
EXPECTED_CHECKS = 24

RECORD = """#!/usr/bin/env bash
printf '%s %s\\n' "$(date +%s.%N)" "$*" >> "$PHONE_EXEC_LOG"
__BODY__
"""

# --json=short shapes lifted from a real busctl against a live KDE Connect
# daemon. The laptop has no battery or connectivity_report leaf, as an
# unpaired device has not: those GetAlls print nothing, which the service
# parses to null.
BUSCTL_BODY = """\
case "$*" in
  *"org.freedesktop.DBus ListNames")
    printf '{"type":"as","data":[[":1.5","org.freedesktop.DBus","org.kde.kdeconnect.daemon"]]}\\n'
    ;;
  *"org.kde.kdeconnect.daemon devices bb false false")
    printf '{"type":"as","data":[["%(laptop)s","%(phone)s"]]}\\n'
    ;;
  *"devices/%(phone)s/battery org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device.battery")
    printf '{"type":"a{sv}","data":[{"charge":{"type":"i","data":85},"hasBattery":{"type":"b","data":true},"isCharging":{"type":"b","data":false}}]}\\n'
    ;;
  *"devices/%(phone)s/connectivity_report org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device.connectivity_report")
    printf '{"type":"a{sv}","data":[{"cellularNetworkStrength":{"type":"i","data":4},"cellularNetworkType":{"type":"s","data":"LTE"},"iconName":{"type":"s","data":"network-mobile-100-lte"}}]}\\n'
    ;;
  *"devices/%(phone)s org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device")
    printf '{"type":"a{sv}","data":[{"name":{"type":"s","data":"Galaxy S23 Ultra"},"type":{"type":"s","data":"phone"},"isPaired":{"type":"b","data":true},"isReachable":{"type":"b","data":true},"isPairRequestedByPeer":{"type":"b","data":false},"pairState":{"type":"i","data":3},"reachableAddresses":{"type":"as","data":["%(phone_address)s"]}}]}\\n'
    ;;
  *"devices/%(laptop)s org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device")
    printf '{"type":"a{sv}","data":[{"name":{"type":"s","data":"rox-xbox-ally-x"},"type":{"type":"s","data":"desktop"},"isPaired":{"type":"b","data":false},"isReachable":{"type":"b","data":true},"isPairRequestedByPeer":{"type":"b","data":true},"pairState":{"type":"i","data":2},"reachableAddresses":{"type":"as","data":["%(laptop_address)s"]}}]}\\n'
    ;;
  *monitor*)
    sleep 3600
    ;;
esac
exit 0
""" % {"phone": PHONE_ID, "laptop": LAPTOP_ID,
       "phone_address": PHONE_ADDRESS, "laptop_address": LAPTOP_ADDRESS}


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
class PhoneTabRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-phone-tab-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.exec_log = self.home / "exec.log"
        self.bin = self.home / "bin"
        self.bin.mkdir(parents=True)
        fake = self.bin / "busctl"
        fake.write_text(RECORD.replace("__BODY__", BUSCTL_BODY))
        fake.chmod(0o755)

        shell_config = self.home / "config" / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        # The poll is ten minutes out: the startup sweep populates the model
        # (the timer fires on start), and nothing may re-sweep while the
        # harness takes a pairing card away through the model and measures
        # what the notification list does with the room.
        #
        # Contacts are off: the nav card's count reads PhoneContacts, whose
        # construction starts a supervised monitor process this harness has
        # nothing for - a backoff ladder running through the run is noise
        # in the log and a process to reap, and the card's "Syncing…" state
        # is the one the harness reads either way.
        (shell_config / "config.json").write_text(json.dumps({
            "networking": {"phoneConnect": {"enable": True, "pollInterval": 600000}},
            "phone": {"contacts": {"enabled": False}},
        }, indent=2))

    def invocations(self):
        if not self.exec_log.exists():
            return []
        return [line.partition(" ")[2] for line in self.exec_log.read_text().splitlines() if line.strip()]

    def test_the_tab_reads_the_model_and_answers_the_pairing_request(self):
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
             f"--socket={SOCKET}", "--width=900", "--height=900"],
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
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["PATH"] = f"{self.bin}{os.pathsep}{env['PATH']}"
        env["PHONE_EXEC_LOG"] = str(self.exec_log)
        env["PHONE_ID"] = PHONE_ID
        env["LAPTOP_ID"] = LAPTOP_ID
        env["PHONE_EXPECT_ADDRESS"] = PHONE_ADDRESS
        env["LAPTOP_EXPECT_ADDRESS"] = LAPTOP_ADDRESS

        # dbus-run-session, not the inherited bus: the fake busctl is the only
        # daemon this harness may see.
        proc = subprocess.run(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\\n{output}")
        self.assertIn(f"[PhoneTab] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\\n{output}")

        # The two clicks, scored off what reached the daemon.
        laptop_path = f"/modules/kdeconnect/devices/{LAPTOP_ID}"
        pairing = [argv for argv in self.invocations()
                   if argv.endswith("acceptPairing") or argv.endswith("cancelPairing")]
        self.assertEqual(
            [argv.rsplit(" ", 1)[1] for argv in pairing], ["acceptPairing", "cancelPairing"],
            f"expected one accept then one decline, got {pairing}")
        for argv in pairing:
            self.assertIn(f"{laptop_path} org.kde.kdeconnect.device", argv,
                          f"a pairing answer was aimed away from the device that asked: {argv}")
            self.assertNotIn(PHONE_ID, argv)


if __name__ == "__main__":
    unittest.main()
