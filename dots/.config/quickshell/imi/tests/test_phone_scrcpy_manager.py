#!/usr/bin/env python3
"""Drives scripts/phone/scrcpy_session_manager.py over its real stdin/stdout
with fake `scrcpy`, `adb` and `hyprctl` binaries first on PATH.

The supervisor is the one process that owns scrcpy children for the Phone
tab, so what is pinned here is the protocol the QML side is written against:
the exact scrcpy argv (target first, then the imi-phone-<type>-<id> window
title, then the caller's flags), the started/exited/error events, focus by
window title through hyprctl, the USB-over-wireless target rule, the app-list
parse with its system marker and its `pm list packages -3` fallback, the
apps_error that keeps a dropped phone from wiping the list on screen, the
cache file the next launch reads back, and the stop-everything-on-EOF that
keeps a shell restart from stranding headless scrcpy windows.
"""
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANAGER = ROOT / "scripts" / "phone" / "scrcpy_session_manager.py"

FAKE_SCRCPY = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG/scrcpy.argv"
case " $* " in
  *" --version "*) echo "scrcpy 4.1 <https://github.com/Genymobile/scrcpy>"; exit 0 ;;
  *" --list-apps "*)
    if [ -n "${FAKE_LIST_APPS:-}" ]; then cat "$FAKE_LIST_APPS"; fi
    exit 0 ;;
esac
if [ -n "${FAKE_SCRCPY_FAIL:-}" ]; then
  echo "WARN: something minor" >&2
  echo "ERROR: Could not find ADB device" >&2
  exit 1
fi
exec sleep 60
"""

FAKE_ADB = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG/adb.argv"
case "$1" in
  devices)
    echo "List of devices attached"
    if [ -n "${FAKE_ADB_DEVICES:-}" ]; then printf '%b\n' "$FAKE_ADB_DEVICES"; fi
    exit 0 ;;
  connect) echo "connected to $2"; exit 0 ;;
  get-state) echo device; exit 0 ;;
esac
case " $* " in
  *" shell pm list packages -3 "*)
    if [ -n "${FAKE_ADB_PM_FAIL:-}" ]; then echo "error: no devices/emulators found" >&2; exit 1; fi
    printf 'package:org.mozilla.firefox\npackage:com.example.second\npackage:org.mozilla.firefox\n'
    exit 0 ;;
esac
exit 0
"""

FAKE_HYPRCTL = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG/hyprctl.argv"
exit 0
"""

LIST_APPS_OUTPUT = """INFO: [server] INFO: List of apps:
 * Settings                    com.android.settings
 - Firefox                     org.mozilla.firefox
 - Signal Private Messenger    org.thoughtcrime.securesms
 * Firefox                     org.mozilla.firefox
this line is not an app
"""


class Supervisor:
    def __init__(self, tmp, env_extra=None):
        self.tmp = Path(tmp)
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.log = self.tmp / "log"
        self.log.mkdir()
        for name, body in (("scrcpy", FAKE_SCRCPY), ("adb", FAKE_ADB), ("hyprctl", FAKE_HYPRCTL)):
            path = self.bin / name
            path.write_text(body)
            path.chmod(0o755)
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}:{env.get('PATH', '')}"
        env["FAKE_LOG"] = str(self.log)
        env["XDG_CACHE_HOME"] = str(self.tmp / "cache")
        env["HOME"] = str(self.tmp)
        env.update(env_extra or {})
        self.proc = subprocess.Popen(
            [sys.executable, str(MANAGER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, env=env, bufsize=1)
        self.events = queue.Queue()
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        for line in self.proc.stdout:
            line = line.strip()
            if line:
                self.events.put(json.loads(line))

    def send(self, **msg):
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()

    def expect(self, event, timeout=8.0, **fields):
        deadline = time.monotonic() + timeout
        seen = []
        while time.monotonic() < deadline:
            try:
                msg = self.events.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            seen.append(msg)
            if msg.get("event") == event and all(msg.get(k) == v for k, v in fields.items()):
                return msg
        raise AssertionError(f"no {event} {fields} within {timeout}s; saw {seen}")

    def argv(self, binary, at_least=1, timeout=5.0):
        """The fake's recorded argv lines. A `started` event is emitted as
        soon as the child is spawned, before the fake has written its log
        line, so this waits for the count the caller expects."""
        path = self.log / f"{binary}.argv"
        deadline = time.monotonic() + timeout
        while True:
            lines = path.read_text().splitlines() if path.exists() else []
            if len(lines) >= at_least or time.monotonic() >= deadline:
                return lines
            time.sleep(0.02)

    def close(self):
        # Idempotent: a test that closes stdin itself is closed again by
        # the cleanup, and the pipes may only be read once.
        if self.proc.stderr.closed:
            return ""
        if self.proc.stdin and not self.proc.stdin.closed:
            self.proc.stdin.close()
        try:
            self.proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        stderr = self.proc.stderr.read()
        self.proc.stderr.close()
        self.proc.stdout.close()
        return stderr


class ScrcpySessionManagerTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)

    def _start(self, **env):
        sup = Supervisor(self.tmpdir.name, env)
        self.addCleanup(sup.close)
        return sup

    def test_launch_builds_target_then_title_then_flags_and_reports_started(self):
        sup = self._start(FAKE_ADB_DEVICES="ABC123\\tdevice")
        sup.send(cmd="launch", id="mirror", type="mirror", target_args=[],
                 extra_args=["--stay-awake", "--max-fps=60"])
        started = sup.expect("started", id="mirror")
        self.assertEqual(started["title"], "imi-phone-mirror-mirror")
        self.assertGreater(started["pid"], 0)
        argv = sup.argv("scrcpy")
        self.assertEqual(argv, ["-s ABC123 --window-title=imi-phone-mirror-mirror --stay-awake --max-fps=60"])

    def test_a_usb_serial_wins_over_a_wireless_one(self):
        sup = self._start(FAKE_ADB_DEVICES="192.168.1.20:5555\\tdevice\\nUSB42\\tdevice")
        sup.send(cmd="launch", id="mirror", type="mirror", target_args=["-s", "192.168.1.20:5555"])
        sup.expect("started", id="mirror")
        self.assertTrue(sup.argv("scrcpy")[0].startswith("-s USB42 "))

    def test_a_wireless_target_is_connected_first_and_stands_when_adb_lists_nothing(self):
        sup = self._start()
        sup.send(cmd="launch", id="mirror", type="mirror", target_args=["-s", "10.0.0.7:5555"])
        sup.expect("started", id="mirror")
        self.assertIn("connect 10.0.0.7:5555", sup.argv("adb"))
        self.assertTrue(sup.argv("scrcpy")[0].startswith("-s 10.0.0.7:5555 --window-title="))

    def test_an_app_session_title_carries_the_package_with_colons_replaced(self):
        sup = self._start()
        sup.send(cmd="launch", id="app:org.mozilla.firefox", type="app",
                 extra_args=["--start-app=org.mozilla.firefox"])
        started = sup.expect("started", id="app:org.mozilla.firefox")
        self.assertEqual(started["title"], "imi-phone-app-app_org.mozilla.firefox")

    def test_launching_a_live_session_again_focuses_it_instead_of_a_second_scrcpy(self):
        sup = self._start()
        sup.send(cmd="launch", id="mirror", type="mirror")
        sup.expect("started", id="mirror")
        sup.send(cmd="launch", id="mirror", type="mirror")
        again = sup.expect("started", id="mirror", alreadyRunning=True)
        self.assertEqual(again["title"], "imi-phone-mirror-mirror")
        self.assertEqual(sup.argv("hyprctl"), ["dispatch focuswindow title:^imi-phone-mirror-mirror$"])
        self.assertEqual(len(sup.argv("scrcpy", at_least=2, timeout=1.0)), 1)

    def test_focus_addresses_the_window_by_its_title(self):
        sup = self._start()
        sup.send(cmd="launch", id="mirror", type="mirror")
        sup.expect("started", id="mirror")
        sup.send(cmd="focus", id="mirror")
        self.assertEqual(sup.argv("hyprctl"), ["dispatch focuswindow title:^imi-phone-mirror-mirror$"])

    def test_stop_ends_the_session_and_reports_exited(self):
        sup = self._start()
        sup.send(cmd="launch", id="mirror", type="mirror")
        started = sup.expect("started", id="mirror")
        sup.send(cmd="stop", id="mirror")
        exited = sup.expect("exited", id="mirror")
        self.assertNotEqual(exited["code"], None)
        self.assertFalse(Path(f"/proc/{started['pid']}").exists() and
                         "sleep" in (Path(f"/proc/{started['pid']}/comm").read_text()
                                     if Path(f"/proc/{started['pid']}/comm").exists() else ""))

    def test_stop_all_ends_every_session(self):
        sup = self._start()
        sup.send(cmd="launch", id="mirror", type="mirror")
        sup.send(cmd="launch", id="app:com.a", type="app")
        sup.expect("started", id="mirror")
        sup.expect("started", id="app:com.a")
        sup.send(cmd="stop_all")
        sup.expect("exited", id="mirror")
        sup.expect("exited", id="app:com.a")

    def test_a_failing_scrcpy_reports_its_last_stderr_line(self):
        sup = self._start(FAKE_SCRCPY_FAIL="1")
        sup.send(cmd="launch", id="mirror", type="mirror")
        sup.expect("started", id="mirror")
        exited = sup.expect("exited", id="mirror")
        self.assertEqual(exited["code"], 1)
        self.assertEqual(exited["error"], "ERROR: Could not find ADB device")

    def test_closing_stdin_stops_every_session(self):
        sup = self._start()
        sup.send(cmd="launch", id="mirror", type="mirror")
        started = sup.expect("started", id="mirror")
        sup.close()
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            comm = Path(f"/proc/{started['pid']}/comm")
            if not comm.exists():
                break
            try:
                if comm.read_text().strip() != "sleep":
                    break
            except OSError:
                break
            time.sleep(0.05)
        else:
            self.fail("the scrcpy child outlived the supervisor's stdin")

    def test_list_apps_parses_the_system_marker_dedupes_and_sorts(self):
        listing = Path(self.tmpdir.name) / "apps.txt"
        listing.write_text(LIST_APPS_OUTPUT)
        sup = self._start(FAKE_LIST_APPS=str(listing), FAKE_ADB_DEVICES="ABC123\\tdevice")
        sup.send(cmd="list_apps", target_args=[], deviceId="dev_1")
        apps = sup.expect("apps_list", deviceId="dev_1")
        self.assertNotIn("cached", apps)
        self.assertEqual(
            apps["apps"],
            [{"package": "org.mozilla.firefox", "name": "Firefox", "system": False},
             {"package": "com.android.settings", "name": "Settings", "system": True},
             {"package": "org.thoughtcrime.securesms", "name": "Signal Private Messenger", "system": False}])
        self.assertIn("-s ABC123 --list-apps", sup.argv("scrcpy"))

    def test_list_apps_falls_back_to_pm_list_when_scrcpy_prints_nothing(self):
        sup = self._start(FAKE_ADB_DEVICES="ABC123\\tdevice")
        sup.send(cmd="list_apps", deviceId="dev_1")
        apps = sup.expect("apps_list", deviceId="dev_1")
        self.assertEqual(
            apps["apps"],
            [{"package": "org.mozilla.firefox", "name": "Firefox", "system": False},
             {"package": "com.example.second", "name": "Second", "system": False}])
        self.assertIn("-s ABC123 shell pm list packages -3", sup.argv("adb"))

    def test_a_phone_off_adb_is_an_error_not_an_empty_list(self):
        sup = self._start(FAKE_ADB_PM_FAIL="1")
        sup.send(cmd="list_apps", deviceId="dev_1")
        error = sup.expect("apps_error")
        self.assertEqual(error["message"], "Phone not reachable over ADB")
        self.assertTrue(all(m.get("event") != "apps_list" for m in list(sup.events.queue)))

    def test_the_app_list_is_cached_per_device_and_served_before_the_next_fetch(self):
        listing = Path(self.tmpdir.name) / "apps.txt"
        listing.write_text(LIST_APPS_OUTPUT)
        sup = self._start(FAKE_LIST_APPS=str(listing))
        sup.send(cmd="list_apps", deviceId="dev_1")
        fresh = sup.expect("apps_list", deviceId="dev_1")
        cache = Path(self.tmpdir.name) / "cache" / "immaterial-impulse" / "phone" / "apps" / "dev_1.json"
        self.assertTrue(cache.exists(), f"no cache at {cache}")
        data = json.loads(cache.read_text())
        self.assertEqual(data["deviceId"], "dev_1")
        self.assertEqual(data["apps"], fresh["apps"])
        self.assertIsInstance(data["generatedAt"], int)

        sup.send(cmd="list_apps", deviceId="dev_1")
        cached = sup.expect("apps_list", deviceId="dev_1", cached=True)
        self.assertEqual(cached["apps"], fresh["apps"])
        sup.expect("apps_list", deviceId="dev_1")

    def test_an_unknown_command_and_a_malformed_line_do_not_end_the_loop(self):
        sup = self._start()
        sup.proc.stdin.write("this is not json\n")
        sup.send(cmd="nonsense")
        sup.send(cmd="launch", id="mirror", type="mirror")
        sup.expect("started", id="mirror")


if __name__ == "__main__":
    unittest.main()
