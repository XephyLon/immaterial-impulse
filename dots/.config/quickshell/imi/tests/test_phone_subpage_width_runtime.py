#!/usr/bin/env python3
"""How wide the Phone tab's Webcam and Microphone sub-pages ask to be.

`PhoneSubPageWidthRuntimeTest.qml` opens both pages inside the real tab, at
the panel's real width, and reads back where every row is DRAWN and what
every row ASKS for. It exists because the pages shipped overflowing
horizontally and nothing could see it: both are a `ContentPage`, whose
content column is `Math.max(baseWidth, implicitWidth)` wide and centred, and
`baseWidth` defaults to the settings window's 600 - so in a 460px sidebar
the column hung off both edges and every label was clipped at the panel's
left edge. The page rendered, the suite stayed green, and `qmltestrunner`
can build neither a laid-out box nor a `ContentPage`.

The long service error (`PhoneCamera.lastError`, the maintainer's own
"DroidCam did not start - is the DroidCam app open on the phone?") is the
same defect from the other end: a `NoticeBox` reports its string's unwrapped
width as its implicit width, so one banner could widen the page past even
that 600.

Two things keep this off the maintainer's machine, and the first one is why
the existing layout harness deliberately does not drive these two pages:
`PhoneMic` runs `pactl get-default-sink` from its own `Component.onCompleted`
and can go on to `pactl set-default-sink`. Every tool `PhoneDeps` probes is
therefore a stub first on PATH - `pactl` included - so the page comes up
"available" without a single command reaching the session's audio. The
daemon is a fake `busctl`, under a session bus of this test's own.

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
HARNESS = ROOT / "PhoneSubPageWidthRuntimeTest.qml"
SOCKET = "wayland-imi-phone-width"

PHONE_ID = "6131a746_571a_4176_a007_95625ff8e08e"
PHONE_NAME = "Galaxy S23 Ultra"
PHONE_ADDRESS = "192.168.100.179"

# A literal, never read back out of the harness's own output: a step list
# that shrinks must redden here instead of reporting `failures: 0` for a
# shorter run.
EXPECTED_CHECKS = 19

BUSCTL = """\
#!/usr/bin/env bash
case "$*" in
  *"org.freedesktop.DBus ListNames")
    printf '{"type":"as","data":[[":1.5","org.freedesktop.DBus","org.kde.kdeconnect.daemon"]]}\\n'
    ;;
  *"org.kde.kdeconnect.daemon devices bb false false")
    printf '{"type":"as","data":[["%(phone)s"]]}\\n'
    ;;
  *"/notifications org.kde.kdeconnect.device.notifications activeNotifications")
    printf '{"type":"as","data":[[]]}\\n'
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

# The tools PhoneDeps probes. Every one of them is here so both pages report
# "available" and draw their real rows - and `pactl` is here so that nothing
# this test starts can reach the session's audio.
STUBS = {
    "pactl": 'case "$*" in\n'
             '  "get-default-sink") echo "alsa_output.fake.stub" ;;\n'
             '  "get-default-source") echo "alsa_input.fake.stub" ;;\n'
             '  "list sink-inputs") : ;;\n'
             'esac\nexit 0\n',
    "scrcpy": 'echo "scrcpy 4.1 <https://github.com/Genymobile/scrcpy>"\nexit 0\n',
    "adb": 'if [ "$1" = "devices" ]; then\n'
           '  printf "List of devices attached\\nR5CT30FAKE\\tdevice\\n"\n'
           'fi\nexit 0\n',
    "droidcam-cli": "exit 0\n",
    "v4l2-ctl": "exit 0\n",
    "mpv": "exit 0\n",
    "ffplay": "exit 0\n",
    "vlc": "exit 0\n",
    "kdialog": "exit 0\n",
    "wl-paste": "exit 0\n",
    # The loopback module, reported as loaded: the webcam page must come up
    # with no "missing dependencies" banner whatever this machine has.
    "lsmod": 'printf "Module Size Used by\\nv4l2loopback 40960 0\\n"\nexit 0\n',
    "modinfo": "exit 0\n",
}


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
class PhoneSubPageWidthRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-phone-width-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

        self.bin = self.home / "bin"
        self.bin.mkdir(parents=True)
        busctl = self.bin / "busctl"
        busctl.write_text(BUSCTL % {
            "phone": PHONE_ID, "name": PHONE_NAME, "address": PHONE_ADDRESS,
        })
        busctl.chmod(0o755)
        for name, body in STUBS.items():
            stub = self.bin / name
            stub.write_text("#!/usr/bin/env bash\n" + body)
            stub.chmod(0o755)

        shell_config = self.home / "config" / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        # The poll is ten minutes out: the startup sweep populates the model
        # and nothing may re-sweep while the harness is measuring geometry.
        (shell_config / "config.json").write_text(json.dumps({
            "networking": {"phoneConnect": {"enable": True, "pollInterval": 600000}},
            "phone": {"contacts": {"enabled": False}},
        }, indent=2))

    def test_neither_sub_page_asks_for_more_width_than_the_panel_has(self):
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

        # dbus-run-session, not the inherited bus: the fake busctl is the only
        # daemon this harness may see.
        proc = subprocess.run(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=300)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[PhoneSubPageWidth] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        # A layout-managed item carrying anchors is a warning, not an error,
        # and it means the item is not where the source says it is.
        self.assertNotIn("Detected anchors on an item that is managed by a layout", output,
                         f"a sub-page's content fights its own layout:\n{output}")


if __name__ == "__main__":
    unittest.main()
