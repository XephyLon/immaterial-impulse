#!/usr/bin/env python3
"""What the Phone tab and its sub-pages draw, measured in a real window.

`PhoneTabLayoutRuntimeTest.qml` builds the real tab over the real services,
opens the Contacts and Android Apps sub-pages and reads the drawn geometry
back. It exists because four defects the maintainer hit are invisible to
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
- a contact card sized from a constant fits one script. Arabic sets taller
  than Latin at the same `pixelSize`, so `Layout.preferredHeight: huge * 2` on
  the row's header drew the avatar flush on the card's bottom edge for a Latin
  name and pushed an Arabic contact's avatar and number out through the bottom
  of the card. An aligned layout child keeps its preferred size when the cell
  is too small - it overflows rather than shrinking - so nothing errors and
  nothing is logged. The fixture therefore carries both scripts.

It also drives the Android Apps page through every state it has, because which
message that page draws is a question about several facts at once and no source
check can ask it. Two families:

- what adb IS on this machine, which used to be one state and is three. `adb`
  is stripped out of the harness's PATH entirely (the maintainer's own lives in
  /opt/android-sdk/platform-tools), and the two stubs are copied in between
  steps: absent, then one that answers the way the dynamic loader does - the
  `error while loading shared libraries` sentence on stderr and exit 127 -
  then one that works. `command -v` reports the middle one as present, which
  is the whole defect: the webcam card read `ready`, the click did nothing, and
  the message pointed at the phone.
- what is ON adb: with no device the page must draw the pairing panel and
  NEITHER of the two lines that used to say the same thing beside it (a red
  "Phone not reachable over ADB" from the session manager, and a "No apps yet"
  empty state that cannot say what to do about it); with a phone that answered
  and had nothing, the empty state and no panel; with apps, the list and no
  message at all.

The pairing panel itself is driven end to end - discovery through a fake
`avahi-browse`, then `adb pair` and `adb connect` through the fake adb, whose
`connect` creates the attach marker so the panel is taken down by the phone
turning up under `adb devices` rather than by adb's own line (which is a claim:
the real `adb connect` exits 0 on a refused connection). It is measured at two
page widths, because a column pinned to one width passes every check at that
width.

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
# 21 shared, 13 for the contact rows' geometry, 44 for the Apps page - the
# three states adb itself can be in, the three states the page can be in, and
# the pairing panel driven through discovery, pair and connect at two widths.
EXPECTED_CHECKS = 78

# The two names the row-geometry steps measure, handed to the harness in the
# environment so the fixture is the only place either is spelled. The Arabic
# one is the maintainer's own screenshot, with the number it carried.
LATIN_NAME = "Alice Rivers"
ARABIC_NAME = "\u0627\u0628\u0648 \u0631\u0648\u0641\u0627\u0646 \u0627\u0644\u0645\u062d\u0644\u0645\u064a"

# The Arabic face is the whole measurement, and this test redirects
# XDG_CONFIG_HOME - which takes the developer's own ~/.config/fontconfig with
# it. Measured: with the redirect and no replacement, an Arabic string in
# "Google Sans Flex" falls back to DejaVu Sans and sets 19px, the same as the
# Latin one, so the row that fits one script fits both and the harness reports
# a defect it cannot see. This is the shape of the shell's own fontconfig, so
# the harness measures the stack the user is looking at rather than whatever
# the machine happens to sort to.
FONTS_CONF = """<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test compare="eq" name="family">
      <string>sans-serif</string>
    </test>
    <edit name="family" mode="prepend" binding="strong">
      <string>Noto Sans</string>
      <string>Noto Sans Arabic</string>
    </edit>
  </match>
</fontconfig>
"""
ARABIC_FACE = "Noto Sans Arabic"

RECORD = """#!/usr/bin/env bash
printf '%s %s\\n' "$(date +%s.%N)" "$*" >> "$PHONE_EXEC_LOG"
__BODY__
"""

# `adb` and `scrcpy`, faked so the Apps page's three states are a property of
# this test rather than of the machine running it. Both are really installed on
# the maintainer's box - which is exactly why they have to be shadowed: with the
# real ones the page reads whatever `adb devices` happens to answer, and the
# state the screenshots were taken in (adb sees nothing) would flip the moment a
# phone is plugged in.
#
# What is attached is a FILE the harness creates between steps, not an argument,
# because the thing being driven is a change the shell has to notice on its own.
# The working adb. `connect` creates the attach marker, so the panel is taken
# down by the phone appearing under `adb devices` rather than by the sentence
# adb printed - which is the distinction that matters, since the real
# `adb connect` exits 0 on a refused connection too.
ADB_BODY = """\
case "$1" in
  --version)
    printf 'Android Debug Bridge version 1.0.41\\n'
    exit 0
    ;;
  devices)
    printf 'List of devices attached\\n'
    if [ -f "$PHONE_ADB_ATTACHED" ]; then printf 'imi-fake-phone\\tdevice\\n'; fi
    exit 0
    ;;
  pair)
    printf 'Successfully paired to %s [guid=adb-imi-fake]\\n' "$2"
    exit 0
    ;;
  connect)
    : > "$PHONE_ADB_ATTACHED"
    printf 'connected to %s\\n' "$2"
    exit 0
    ;;
esac
# Every other adb call - `shell pm list packages -3` is the one the session
# manager falls back to - fails while nothing is attached, which is what tells
# it apart from a phone that answered with no apps.
[ -f "$PHONE_ADB_ATTACHED" ] || exit 1
exit 0
"""

# An adb that is on PATH and cannot start, spelled exactly the way the dynamic
# loader spells it: the sentence on stderr, nothing on stdout, and 127. This is
# what droidcam-cli did on the maintainer's machine while `command -v` reported
# it present.
ADB_BROKEN_LIB = "libimi-not-a-real-library.so.7"
ADB_BROKEN_BODY = """\
printf '%s: error while loading shared libraries: %s: cannot open shared object file: No such file or directory\\n' \\
  "$0" "$PHONE_ADB_BROKEN_LIB" >&2
exit 127
"""

# The two service types Android advertises while wireless debugging is on, in
# avahi's parsable resolved form. The unresolved `+` line is there because the
# parser has to skip one.
AVAHI_BODY = """\
case "$*" in
  *_adb-tls-pairing._tcp*)
    printf '+;wlan0;IPv4;adb-imi-fake;_adb-tls-pairing._tcp;local\\n'
    printf '=;wlan0;IPv4;adb-imi-fake;_adb-tls-pairing._tcp;local;phone.local;%s;37129;\\n' \\
      "$PHONE_LAN_ADDRESS"
    ;;
  *_adb-tls-connect._tcp*)
    printf '=;wlan0;IPv4;adb-imi-fake;_adb-tls-connect._tcp;local;phone.local;%s;41235;\\n' \\
      "$PHONE_LAN_ADDRESS"
    ;;
esac
exit 0
"""

SCRCPY_BODY = """\
case "$*" in
  *--version*)
    printf 'scrcpy 4.1 <https://github.com/Genymobile/scrcpy>\\n'
    exit 0
    ;;
  *--list-apps*)
    if [ -f "$PHONE_APPS_FILE" ]; then cat "$PHONE_APPS_FILE"; fi
    exit 0
    ;;
esac
exit 0
"""

# `scrcpy --list-apps` prints `* ` for a system app and `- ` for a user one.
APP_LINES = """\
 * Settings                        com.android.settings
 - Signal                          org.thoughtcrime.securesms
 - Firefox                         org.mozilla.firefox
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

# Four cards shaped after what Android's exporter writes: three named
# contacts and one that is nothing but a number, so `hideUnnamed` has
# something to hide and the list still has rows. One of the three is Arabic,
# because the row's height is a function of the script and a fixture in one
# script cannot say so.
VCARDS = {
    "alice.vcf": (
        "BEGIN:VCARD\n"
        "VERSION:3.0\n"
        "UID:alice-uid-1\n"
        f"FN:{LATIN_NAME}\n"
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
    "rufan.vcf": (
        "BEGIN:VCARD\n"
        "VERSION:3.0\n"
        "UID:rufan-uid-1\n"
        f"FN:{ARABIC_NAME}\n"
        f"N:;{ARABIC_NAME};;;\n"
        "TEL;TYPE=CELL,PREF:+201016000286\n"
        "EMAIL;TYPE=WORK:rufan@example.com\n"
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


def _arabic_face_available():
    """Whether the face the row-geometry steps measure against is installed.

    Without it the Arabic name sets at the Latin face's height and the two
    cards come out the same, which reads as "the row is fine" rather than as
    "the measurement never happened" - so it is a skip with a reason, not a
    red check.
    """
    if not shutil.which("fc-list"):
        return False
    probe = subprocess.run(["fc-list", "--format=%{family}\n"],
                           capture_output=True, text=True)
    return ARABIC_FACE in probe.stdout


@unittest.skipUnless(_runtime_available(), "needs qs, weston and dbus-run-session on PATH")
class PhoneTabLayoutRuntimeTest(unittest.TestCase):
    def setUp(self):
        if not _arabic_face_available():
            self.skipTest(f"needs {ARABIC_FACE} to measure an Arabic row")
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

        # Neither marker exists yet: the page opens in the state the
        # screenshots were taken in, with no phone on ADB at all.
        self.adb_attached = self.home / "adb-attached"
        self.apps_file = self.home / "apps.txt"
        # Staged beside it rather than written in place: the harness copies it
        # over when it wants the third state, so the second state ("the phone
        # answered with nothing") is a real empty answer from a real device.
        self.apps_source = self.home / "apps-source.txt"
        self.apps_source.write_text(APP_LINES)
        # scrcpy and avahi-browse are on PATH from the start; `adb` is NOT.
        # It is staged beside them and copied in by the harness, which is the
        # only way a test can say what `command -v adb` answers - the machine
        # this runs on has one, and the first state the page has to draw is
        # the one where it does not.
        for name, body in (("scrcpy", SCRCPY_BODY), ("avahi-browse", AVAHI_BODY)):
            tool = self.bin / name
            tool.write_text(RECORD.replace("__BODY__", body))
            tool.chmod(0o755)
        self.adb_bin = self.bin / "adb"
        self.adb_ok = self.home / "adb-ok"
        self.adb_broken = self.home / "adb-broken"
        self.adb_ok.write_text(RECORD.replace("__BODY__", ADB_BODY))
        self.adb_ok.chmod(0o755)
        self.adb_broken.write_text(RECORD.replace("__BODY__", ADB_BROKEN_BODY))
        self.adb_broken.chmod(0o755)

        # The vCards KDE Connect writes for KPeople, which the real monitor
        # reads: a fixture tree, never the machine's own contacts.
        cards = self.home / "data" / "kpeoplevcard" / f"kdeconnect-{PHONE_ID}"
        cards.mkdir(parents=True)
        for name, body in VCARDS.items():
            (cards / name).write_text(body, encoding="utf-8")

        fontconfig = self.home / "config" / "fontconfig"
        fontconfig.mkdir(parents=True)
        (fontconfig / "fonts.conf").write_text(FONTS_CONF)

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
        # Every directory holding an `adb` comes out: this test decides
        # whether adb exists, and on the maintainer's machine it lives in
        # /opt/android-sdk/platform-tools rather than anywhere a stub could
        # shadow it (`command -v` searches the whole of PATH, so a
        # non-executable placeholder in front would simply be skipped).
        inherited = [d for d in env["PATH"].split(os.pathsep)
                     if d and not (Path(d) / "adb").exists()]
        env["PATH"] = os.pathsep.join([str(self.bin)] + inherited)
        self.assertIsNone(shutil.which("adb", path=env["PATH"]),
                          "adb is still reachable, so the absent state is not a state")
        env["PHONE_EXEC_LOG"] = str(self.exec_log)
        env["PHONE_ID"] = PHONE_ID
        env["PHONE_ICON_PATH"] = str(self.icon_path)
        env["PHONE_CONTACT_LATIN"] = LATIN_NAME
        env["PHONE_CONTACT_ARABIC"] = ARABIC_NAME
        env["PHONE_ADB_ATTACHED"] = str(self.adb_attached)
        env["PHONE_APPS_FILE"] = str(self.apps_file)
        env["PHONE_APPS_SOURCE"] = str(self.apps_source)
        env["PHONE_ADB_BIN"] = str(self.adb_bin)
        env["PHONE_ADB_OK"] = str(self.adb_ok)
        env["PHONE_ADB_BROKEN"] = str(self.adb_broken)
        env["PHONE_ADB_BROKEN_LIB"] = ADB_BROKEN_LIB
        env["PHONE_LAN_ADDRESS"] = PHONE_ADDRESS

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
