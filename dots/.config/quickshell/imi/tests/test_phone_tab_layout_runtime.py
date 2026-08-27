#!/usr/bin/env python3
"""What the Phone tab and its sub-pages draw, measured in a real window.

`PhoneTabLayoutRuntimeTest.qml` builds the real tab over the real services,
opens the Contacts and Android Apps sub-pages and reads the drawn geometry
back. It exists because three defects the maintainer hit are invisible to
every other check in this suite:

- a sub-page whose content resolves to ZERO height renders its header and
  nothing else. `PhoneContactsPage` drew "147 of 150 contacts" over an empty
  list area, and the source reads perfectly: the list states
  `Layout.fillHeight`, its parent states `Layout.fillHeight`, and the page's
  root column states it too. Only the numbers show that the column was never
  in a layout at all.
- `PagePlaceholder` centres its column in itself and clips nothing, so an
  empty state given a zero-height region paints its glyph OVER the search row
  above it. That is one symptom of the same cause, on the page whose list
  happens to be empty rather than full.
- an app icon that is never drawn, and one whose file failed to load, are the
  same source. Only `Image.status` tells them apart.

The fake `busctl` serves one paired, reachable phone and two mirrored
notifications: leaf 70 carries an `iconPath` (a PNG this test writes, the way
kdeconnectd writes one per notification icon into its cache) and leaf 71
carries none, so both the icon and its fallback are on screen at once. The
Contacts page is fed by the REAL contacts monitor over a real
`kpeoplevcard/kdeconnect-<id>/` fixture tree, because a list with no rows
cannot answer "does a row draw at a real height".

Brings its own headless weston and its own session bus (`dbus-run-session`).
Skips when weston, qs or dbus-run-session are missing, as in CI.
"""

import json
import os
import shutil
import struct
import subprocess
import tempfile
import time
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "PhoneTabLayoutRuntimeTest.qml"
SOCKET = "wayland-imi-phone-layout"

PHONE_ID = "6131a746_571a_4176_a007_95625ff8e08e"
PHONE_NAME = "Galaxy S23 Ultra"
PHONE_ADDRESS = "192.168.100.179"

# A literal, never read back out of the harness's own output: a step list
# that shrinks must redden here instead of reporting `failures: 0` for a
# shorter run.
EXPECTED_CHECKS = 20

RECORD = """#!/usr/bin/env bash
printf '%s %s\\n' "$(date +%s.%N)" "$*" >> "$PHONE_EXEC_LOG"
__BODY__
"""

# --json=short shapes lifted from a real busctl against a live KDE Connect
# daemon. Leaf 70 is the captured Truecaller notification with its real
# iconPath shape (an absolute path to a file the daemon wrote); leaf 71 is a
# WhatsApp message, which arrived with no icon at all.
BUSCTL_BODY = """\
case "$*" in
  *"org.freedesktop.DBus ListNames")
    printf '{"type":"as","data":[[":1.5","org.freedesktop.DBus","org.kde.kdeconnect.daemon"]]}\\n'
    ;;
  *"org.kde.kdeconnect.daemon devices bb false false")
    printf '{"type":"as","data":[["%(phone)s"]]}\\n'
    ;;
  *"/notifications org.kde.kdeconnect.device.notifications activeNotifications")
    printf '{"type":"as","data":[["70","71"]]}\\n'
    ;;
  *"/notifications/70 org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device.notifications.notification")
    printf '{"type":"a{sv}","data":[{"appName":{"type":"s","data":"Truecaller"},"dismissable":{"type":"b","data":true},"hasIcon":{"type":"b","data":true},"iconPath":{"type":"s","data":"%(icon)s"},"internalId":{"type":"s","data":"0|com.truecaller|2131366136|null|10553"},"replyId":{"type":"s","data":""},"silent":{"type":"b","data":false},"text":{"type":"s","data":"Allow Truecaller to run in the background"},"ticker":{"type":"s","data":"Stay protected"},"title":{"type":"s","data":"Stay protected 24/7"}}]}\\n'
    ;;
  *"/notifications/71 org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device.notifications.notification")
    printf '{"type":"a{sv}","data":[{"appName":{"type":"s","data":"WhatsApp"},"dismissable":{"type":"b","data":true},"hasIcon":{"type":"b","data":false},"iconPath":{"type":"s","data":""},"internalId":{"type":"s","data":"0|com.whatsapp|1|N3JGW5Lg6vbO|10466"},"replyId":{"type":"s","data":"r1"},"silent":{"type":"b","data":false},"text":{"type":"s","data":"see you at 8"},"ticker":{"type":"s","data":"Sam: see you at 8"},"title":{"type":"s","data":"Sam"}}]}\\n'
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
    sleep 3600
    ;;
esac
exit 0
"""

# Three cards shaped after what Android's exporter writes: two named contacts
# and one that is nothing but a number, so `hideUnnamed` has something to
# hide and the list still has rows.
VCARDS = {
    "alice.vcf": (
        "BEGIN:VCARD\n"
        "VERSION:3.0\n"
        "UID:alice-uid-1\n"
        "FN:Alice Rivers\n"
        "N:Rivers;Alice;;;\n"
        "TEL;TYPE=CELL,PREF:+1 (555) 010-0001\n"
        "EMAIL;TYPE=HOME:alice@example.com\n"
        "END:VCARD\n"
    ),
    "bob.vcf": (
        "BEGIN:VCARD\n"
        "VERSION:3.0\n"
        "UID:bob-uid-1\n"
        "FN:Bob Stone\n"
        "N:Stone;Bob;;;\n"
        "TEL;TYPE=HOME:555 010 0002\n"
        "END:VCARD\n"
    ),
    "nameless.vcf": (
        "BEGIN:VCARD\n"
        "VERSION:3.0\n"
        "UID:sim-0003\n"
        "FN:+15550100003\n"
        "N:;+15550100003;;;\n"
        "TEL;TYPE=CELL:+1 (555) 010-0003\n"
        "END:VCARD\n"
    ),
}


def _png(width=90, height=90):
    """A real PNG, because Image.status is the whole point of the icon check."""
    raw = b"".join(b"\x00" + bytes([220, 60, 60, 255]) * width for _ in range(height))

    def chunk(tag, payload):
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


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
class PhoneTabLayoutRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-phone-layout-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.exec_log = self.home / "exec.log"

        # The notification icon, where the daemon would have put it.
        icons = self.home / "cache" / "kdeconnect-icons"
        icons.mkdir(parents=True)
        self.icon_path = icons / "eb39605216ceabbbd952b1ab18d00267"
        self.icon_path.write_bytes(_png())

        self.bin = self.home / "bin"
        self.bin.mkdir(parents=True)
        fake = self.bin / "busctl"
        fake.write_text(RECORD.replace("__BODY__", BUSCTL_BODY % {
            "phone": PHONE_ID, "name": PHONE_NAME, "address": PHONE_ADDRESS,
            "icon": self.icon_path,
        }))
        fake.chmod(0o755)

        # The vCards KDE Connect writes for KPeople, which the real monitor
        # reads: a fixture tree, never the machine's own contacts.
        cards = self.home / "data" / "kpeoplevcard" / f"kdeconnect-{PHONE_ID}"
        cards.mkdir(parents=True)
        for name, body in VCARDS.items():
            (cards / name).write_text(body)

        shell_config = self.home / "config" / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        # The poll is ten minutes out: the startup sweep populates the model
        # and nothing may re-sweep while the harness is measuring geometry.
        (shell_config / "config.json").write_text(json.dumps({
            "networking": {"phoneConnect": {"enable": True, "pollInterval": 600000}},
            "phone": {"contacts": {"enabled": True, "hideUnnamed": True}},
        }, indent=2))

    def test_the_pages_lay_out_and_a_notification_card_draws_its_icon(self):
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
             f"--socket={SOCKET}", "--width=900", "--height=1000"],
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
        env["PHONE_ICON_PATH"] = str(self.icon_path)

        # dbus-run-session, not the inherited bus: the fake busctl is the only
        # daemon this harness may see.
        proc = subprocess.run(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=300)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[PhoneTabLayout] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        # A layout-managed item carrying anchors is a warning, not an error,
        # and it means the item is not where the source says it is.
        self.assertNotIn("Detected anchors on an item that is managed by a layout", output,
                         f"a sub-page's content fights its own layout:\n{output}")


if __name__ == "__main__":
    unittest.main()
