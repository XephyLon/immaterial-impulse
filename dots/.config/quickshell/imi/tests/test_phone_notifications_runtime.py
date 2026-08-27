#!/usr/bin/env python3
"""The phone's notification mirror, driven against a fake daemon in a real shell.

`PhoneNotificationsRuntimeTest.qml` runs the real `services/PhoneNotifications.qml`
over the real `services/PhoneConnect.qml`, with a fake `busctl` on PATH
exposing one paired, reachable phone. The fake is stateful: its
`activeNotifications` answers from a file holding one public id, its
`monitor` verb adds a second id to that file and prints one
`notificationPosted` signal line, and its leaf `dismiss` removes the id it
was aimed at. The harness reads the model back - the sweep's one
notification with the leaf's fields and the package, the groups, the dedupe
gate, the SECOND notification arriving from the signal (the oracle for the
trigger chain: PhoneConnect's allowlist, its settle, deviceChangeSettled(),
the refetch - with the reconcile a minute out and PhoneConnect's poll ten
minutes out, nothing else can deliver it), the cache landing in Persistent,
and the local effect of dismiss, reply and dismissAll.

The writes are scored HERE, off the fake's recorded invocations:
- `dismiss` reached the LEAF path (`…/notifications/<id>`) on the leaf
  interface's own `dismiss` method, once for 70 and once for 71 - and never
  as a device-level `sendAction … cancel`;
- `sendReply` reached the device-level interface as the two-string call
  with the notification's reply id, exactly once (the empty reply and the
  reply to a notification with no reply id reached nothing);
- `sendAction` reached the same interface keyed on the internalId;
- the refetch after the reply landed no sooner than the declared 800ms;
- exactly ONE busctl monitor was spawned in the whole run - PhoneConnect's.

A click that reached nothing would leave the harness green (the card goes
either way) and this red.

Brings its own headless weston and its own session bus (`dbus-run-session`).
Skips when weston, qs or dbus-run-session are missing, as in CI.
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
HARNESS = ROOT / "PhoneNotificationsRuntimeTest.qml"
SOCKET = "wayland-imi-phonenotifications"

PHONE_ID = "6131a746_571a_4176_a007_95625ff8e08e"
PHONE_NAME = "Galaxy S23 Ultra"
PHONE_ADDRESS = "192.168.100.179"
NOTIFICATIONS_PATH = f"/modules/kdeconnect/devices/{PHONE_ID}/notifications"
DEVICE_IFACE = "org.kde.kdeconnect.device.notifications"
LEAF_IFACE = f"{DEVICE_IFACE}.notification"

# The service's own declared delay, read out of the source rather than copied.
REPLY_REFETCH_DELAY = int(re.search(
    r"readonly property int replyRefetchDelay:\s*(\d+)",
    (ROOT / "services" / "PhoneNotifications.qml").read_text()).group(1)) / 1000

# A literal, never read back out of the harness's own output: a step list
# that shrinks must redden here instead of reporting `failures: 0` for a
# shorter run.
EXPECTED_CHECKS = 16

RECORD = """#!/usr/bin/env bash
printf '%s %s\\n' "$(date +%s.%N)" "$*" >> "$PHONE_EXEC_LOG"
__BODY__
"""

# --json=short shapes lifted from a real busctl against a live KDE Connect
# daemon (2026-08-27): the device's activeNotifications is a list of PUBLIC
# ids, and leaf 70 is the captured Truecaller notification verbatim. Leaf 71
# is the same shape carrying a reply id.
BUSCTL_BODY = """\
state="$PHONE_STATE_DIR"
active_json() {
  local out="" id
  for id in $(cat "$state/active" 2>/dev/null); do
    out="$out${out:+,}\\"$id\\""
  done
  printf '{"type":"as","data":[[%%s]]}\\n' "$out"
}
case "$*" in
  *"org.freedesktop.DBus ListNames")
    printf '{"type":"as","data":[[":1.5","org.freedesktop.DBus","org.kde.kdeconnect.daemon"]]}\\n'
    ;;
  *"org.kde.kdeconnect.daemon devices bb false false")
    printf '{"type":"as","data":[["%(phone)s"]]}\\n'
    ;;
  *"/notifications org.kde.kdeconnect.device.notifications activeNotifications")
    active_json
    ;;
  *"/notifications/70 org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device.notifications.notification")
    printf '{"type":"a{sv}","data":[{"appName":{"type":"s","data":"Truecaller"},"dismissable":{"type":"b","data":true},"groupName":{"type":"s","data":""},"hasIcon":{"type":"b","data":true},"iconPath":{"type":"s","data":"/tmp/kdeconnect_xephy/eb39605216ceabbbd952b1ab18d00267"},"internalId":{"type":"s","data":"0|com.truecaller|2131366136|null|10553"},"isConversation":{"type":"b","data":false},"isGroupConversation":{"type":"b","data":false},"replyId":{"type":"s","data":""},"silent":{"type":"b","data":false},"text":{"type":"s","data":"Allow Truecaller to run in the background to identify and block calls while you are not using the app"},"ticker":{"type":"s","data":"Stay protected 24/7: Allow Truecaller to run in the background to identify and block calls while you are not using the app"},"title":{"type":"s","data":"Stay protected 24/7"}}]}\\n'
    ;;
  *"/notifications/71 org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device.notifications.notification")
    printf '{"type":"a{sv}","data":[{"appName":{"type":"s","data":"WhatsApp"},"dismissable":{"type":"b","data":true},"groupName":{"type":"s","data":""},"hasIcon":{"type":"b","data":false},"iconPath":{"type":"s","data":""},"internalId":{"type":"s","data":"0|com.whatsapp|1|N3JGW5Lg6vbO|10466"},"isConversation":{"type":"b","data":true},"isGroupConversation":{"type":"b","data":false},"replyId":{"type":"s","data":"r1"},"silent":{"type":"b","data":false},"text":{"type":"s","data":"see you at 8"},"ticker":{"type":"s","data":"Sam: see you at 8"},"title":{"type":"s","data":"Sam"}}]}\\n'
    ;;
  *"/notifications/"*" org.kde.kdeconnect.device.notifications.notification dismiss")
    # $* joined first: a suffix strip on $* itself applies per argument.
    argv="$*"
    id="${argv%% org.kde.kdeconnect.device.notifications.notification dismiss}"
    id="${id##*/}"
    grep -v -x "$id" "$state/active" > "$state/active.next" || true
    mv "$state/active.next" "$state/active"
    ;;
  *"devices/%(phone)s/battery org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device.battery")
    printf '{"type":"a{sv}","data":[{"charge":{"type":"i","data":85},"hasBattery":{"type":"b","data":true},"isCharging":{"type":"b","data":false}}]}\\n'
    ;;
  *"devices/%(phone)s/connectivity_report org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device.connectivity_report")
    printf '{"type":"a{sv}","data":[{"cellularNetworkStrength":{"type":"i","data":4},"cellularNetworkType":{"type":"s","data":"LTE"},"iconName":{"type":"s","data":"network-mobile-100-lte"}}]}\\n'
    ;;
  *"devices/%(phone)s org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device")
    printf '{"type":"a{sv}","data":[{"name":{"type":"s","data":"%(name)s"},"type":{"type":"s","data":"phone"},"isPaired":{"type":"b","data":true},"isReachable":{"type":"b","data":true},"isPairRequestedByPeer":{"type":"b","data":false},"pairState":{"type":"i","data":3},"reachableAddresses":{"type":"as","data":["%(address)s"]}}]}\\n'
    ;;
  *monitor*)
    sleep 1.5
    printf '70\\n71\\n' > "$state/active"
    printf '{"type":"signal","endian":"l","flags":1,"version":1,"cookie":410,"timestamp-realtime":1787149977815500,"sender":":1.55","path":"%(path)s","interface":"org.kde.kdeconnect.device.notifications","member":"notificationPosted","payload":{"type":"s","data":["71"]}}\\n'
    sleep 3600
    ;;
esac
exit 0
""" % {"phone": PHONE_ID, "name": PHONE_NAME, "address": PHONE_ADDRESS, "path": NOTIFICATIONS_PATH}


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
class PhoneNotificationsRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-phonenotifications-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.exec_log = self.home / "exec.log"
        self.state = self.home / "phone-state"
        self.state.mkdir()
        (self.state / "active").write_text("70\n")
        self.bin = self.home / "bin"
        self.bin.mkdir(parents=True)
        fake = self.bin / "busctl"
        fake.write_text(RECORD.replace("__BODY__", BUSCTL_BODY))
        fake.chmod(0o755)

        shell_config = self.home / "config" / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        # PhoneConnect's poll is ten minutes out: the startup sweep populates
        # the device model (the timer fires on start) and nothing re-sweeps
        # on a schedule, so the second notification can only arrive through
        # the signal.
        (shell_config / "config.json").write_text(json.dumps({
            "networking": {"phoneConnect": {"enable": True, "pollInterval": 600000}},
        }, indent=2))

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

    def test_the_mirror_reads_the_leaves_and_writes_to_the_daemon(self):
        env = dict(os.environ)
        runtime = self.home / "runtime"
        runtime.mkdir(mode=0o700)
        env["XDG_RUNTIME_DIR"] = str(runtime)
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=800", "--height=600"],
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
        env["PHONE_STATE_DIR"] = str(self.state)
        env["PHONE_ID"] = PHONE_ID
        env["PHONE_NAME"] = PHONE_NAME

        # dbus-run-session, not the inherited bus: the fake busctl is the only
        # daemon this harness may see.
        proc = subprocess.run(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}\n{self.exec_log.read_text() if self.exec_log.exists() else ''}")
        self.assertIn(f"[PhoneNotifications] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        calls = self.invocations()
        argvs = [argv for _, argv in calls]

        # dismiss: the LEAF's own method, on the leaf path, once per id.
        dismissed = [argv for argv in argvs if argv.endswith(f" {LEAF_IFACE} dismiss")]
        self.assertEqual(
            [argv.split(" ")[-3].rsplit("/", 1)[1] for argv in dismissed], ["70", "71"],
            f"expected dismiss on leaf 70 then leaf 71, got {dismissed}")
        for argv in dismissed:
            self.assertIn(f"{NOTIFICATIONS_PATH}/", argv)
        self.assertEqual([argv for argv in argvs if "cancel" in argv], [], "a cancel action reached the daemon")

        # reply: the device-level two-string call with the reply id, once.
        replies = [argv for argv in argvs if f" {DEVICE_IFACE} sendReply " in argv]
        self.assertEqual(replies, [
            f"--user --json=short --timeout=5 call org.kde.kdeconnect.daemon {NOTIFICATIONS_PATH} {DEVICE_IFACE} sendReply ss r1 hi there"
        ])
        actions = [argv for argv in argvs if f" {DEVICE_IFACE} sendAction " in argv]
        self.assertEqual(actions, [
            f"--user --json=short --timeout=5 call org.kde.kdeconnect.daemon {NOTIFICATIONS_PATH} {DEVICE_IFACE} sendAction ss 0|com.whatsapp|1|N3JGW5Lg6vbO|10466 Mark as read"
        ])

        # The refetch after the reply: the next activeNotifications after
        # sendReply lands no sooner than the declared delay.
        reply_at = next(stamp for stamp, argv in calls if f" {DEVICE_IFACE} sendReply " in argv)
        refetches = [stamp for stamp, argv in calls
                     if argv.endswith(f" {DEVICE_IFACE} activeNotifications") and stamp > reply_at]
        self.assertTrue(refetches, "no refetch followed the reply")
        gap = refetches[0] - reply_at
        self.assertGreaterEqual(gap, REPLY_REFETCH_DELAY, f"the refetch came {gap:.2f}s after the reply")
        self.assertLess(gap, REPLY_REFETCH_DELAY + 2.5, f"the refetch came {gap:.2f}s after the reply")

        # One stream: PhoneConnect's monitor and nobody else's.
        monitors = [argv for argv in argvs if " monitor " in argv]
        self.assertEqual(len(monitors), 1, f"expected exactly one busctl monitor, got {monitors}")

        # The cache reached the disk, keyed by the device.
        states = list((self.home / "state").rglob("states.json"))
        self.assertEqual(len(states), 1, f"expected one states.json, found {states}")
        cache = json.loads(json.loads(states[0].read_text())["phone"]["cachedNotificationsJson"])
        self.assertIn(PHONE_ID, cache)


if __name__ == "__main__":
    unittest.main()
