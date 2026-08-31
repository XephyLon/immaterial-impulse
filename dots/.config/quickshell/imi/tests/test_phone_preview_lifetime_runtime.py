#!/usr/bin/env python3
"""The webcam preview player is gone after every way the session can end.

`PhonePreviewLifetimeRuntimeTest.qml` opens the preview over a stub DroidCam
session and then ends that session five different ways, asking `kill -0` about
the player's own pid each time. It exists because the player used to be
spawned with `Quickshell.execDetached`, which returns no handle: `stop()`
killed the stream and nothing could kill the player, so its window stayed on
screen frozen on the last frame a dead /dev/videoN produced. A check on the
service's own state would have passed on that bug in every one of these cases -
the flag it reads is not what was left running.

Four of the five endings are the harness's; the fifth is this file's. The
harness deliberately exits with a preview still up, and the assertions below
ask the kernel afterwards, with a control process this driver started so that
"gone" cannot be what a broken liveness check says about everything.

The fakes are the load-bearing part, and one of them is not a convenience:
`droidcam-cli` cannot run on this machine at all - it is built against ffmpeg 8
where the system has 9, so it dies on `libswscale.so.9` before doing anything -
so there is no version of this test that drives the real tool. The stub of that
name prints the `Video: /dev/videoN` line the session script greps for and then
sits still until it is signalled, and the REAL scripts/phone/droidcam_session.sh
launches it, so the pidfile, the `status` verb and the `stop` verb under test
are the shell's own. Every other tool `PhoneDeps` probes is stubbed too - the
reason the sibling width harness gives, plus one of this test's own: `pactl` is
here so nothing it starts can reach the session's audio, and `mpv` is here so
nothing it starts can open a window on the maintainer's screen.

Brings its own headless weston, its own XDG directories and its own session bus
(`dbus-run-session`). Skips when weston, qs or dbus-run-session are missing, as
in CI.
"""

import json
import os
import shutil
import signal
import subprocess

import nested_display
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "PhonePreviewLifetimeRuntimeTest.qml"
SESSION_SCRIPT = ROOT / "scripts" / "phone" / "droidcam_session.sh"
SOCKET = "wayland-imi-preview-life"

PHONE_ID = "6131a746_571a_4176_a007_95625ff8e08e"
PHONE_NAME = "Galaxy S23 Ultra"
PHONE_ADDRESS = "192.168.100.179"

# A literal, never read back out of the harness's own output: a step list that
# loses a round must redden here instead of reporting `failures: 0` for a
# shorter run.
EXPECTED_CHECKS = 18

# The daemon, with one switch: while PHONE_ABSENT_MARKER exists it reports no
# devices at all, which is how the harness makes the phone leave without
# writing to the shell's own model.
BUSCTL = """\
#!/usr/bin/env bash
absent=0
if [ -n "${PHONE_ABSENT_MARKER:-}" ] && [ -f "$PHONE_ABSENT_MARKER" ]; then absent=1; fi
case "$*" in
  *"org.freedesktop.DBus ListNames")
    printf '{"type":"as","data":[[":1.5","org.freedesktop.DBus","org.kde.kdeconnect.daemon"]]}\\n'
    ;;
  *"org.kde.kdeconnect.daemon devices bb false false")
    if [ "$absent" = "1" ]; then
      printf '{"type":"as","data":[[]]}\\n'
    else
      printf '{"type":"as","data":[["%(phone)s"]]}\\n'
    fi
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
    # `exec`, so the pid the shell holds IS the sleep: a bash that merely
    # waits on one leaves the sleep behind as an orphan every time the
    # harness exits, which is how the machine collects an hour's worth of
    # them over a few runs.
    exec sleep 3600
    ;;
esac
exit 0
"""

# The stream: it announces its node the way droidcam-cli does (the session
# script greps that line out of the log to answer `device`), then stays alive
# until something signals it. It must NOT `exec` anything: droidcam_session.sh
# refuses to kill a pid whose cmdline has stopped looking like droidcam's, and
# an exec would rewrite exactly that.
DROIDCAM = """\
echo "Video: /dev/video42"
trap 'exit 0' TERM INT
left=900
while [ "$left" -gt 0 ]; do
  sleep 1 &
  wait $! 2>/dev/null || true
  left=$((left - 1))
done
exit 0
"""

# The player: it records its own pid and then behaves like mpv on a live
# capture device - alive until killed. `exec` is right here (nothing greps this
# cmdline) and keeps the pid it just wrote.
MPV = """\
echo $$ > "$PREVIEW_PIDFILE"
exec sleep 900
"""

ADB = """\
case "${1:-}" in
  get-state) echo "device" ;;
  devices)
    echo "List of devices attached"
    printf 'R5CT30FAKE\\tdevice\\n'
    ;;
esac
exit 0
"""

# Every tool PhoneDeps probes, so the webcam reports itself available and no
# probe reaches a real one.
STUBS = {
    "droidcam-cli": DROIDCAM,
    "mpv": MPV,
    "adb": ADB,
    "pactl": 'case "$*" in\n'
             '  "get-default-sink") echo "alsa_output.fake.stub" ;;\n'
             '  "get-default-source") echo "alsa_input.fake.stub" ;;\n'
             'esac\nexit 0\n',
    "scrcpy": 'echo "scrcpy 4.1 <https://github.com/Genymobile/scrcpy>"\nexit 0\n',
    "v4l2-ctl": "exit 0\n",
    "ffplay": "exit 0\n",
    "vlc": "exit 0\n",
    "kdialog": "exit 0\n",
    "wl-paste": "exit 0\n",
    # Reported loaded, so the webcam is available whatever this machine has.
    "lsmod": 'echo "Module Size Used by"\necho "v4l2loopback 40960 0"\nexit 0\n',
    "modinfo": "exit 0\n",
}


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def _alive(pid):
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except (ProcessLookupError, PermissionError):
        return False
    return True


def _runtime_available():
    return all(shutil.which(name) for name in ("qs", "weston", "dbus-run-session"))


@unittest.skipUnless(_runtime_available(), "needs qs, weston and dbus-run-session on PATH")
class PhonePreviewLifetimeRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-preview-life-"))
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

        self.pidfile = self.home / "preview.pid"
        self.absent_marker = self.home / "phone-absent"

        shell_config = self.home / "config" / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        # The poll is ten minutes out: the startup sweep populates the model,
        # and the only other sweep in the run is the refresh() the harness asks
        # for when it makes the phone leave and come back. A live poll would
        # answer that question on its own schedule instead.
        (shell_config / "config.json").write_text(json.dumps({
            "networking": {"phoneConnect": {"enable": True, "pollInterval": 600000}},
            "phone": {"contacts": {"enabled": False}},
        }, indent=2))

    def _env(self):
        env = dict(os.environ)
        runtime = self.home / "runtime"
        runtime.mkdir(mode=0o700, exist_ok=True)
        env["XDG_RUNTIME_DIR"] = str(runtime)
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        env["QT_QUICK_BACKEND"] = "software"
        env["XDG_CONFIG_HOME"] = str(self.home / "config")
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["PATH"] = f"{self.bin}{os.pathsep}{env['PATH']}"
        env["PREVIEW_PIDFILE"] = str(self.pidfile)
        env["PHONE_ABSENT_MARKER"] = str(self.absent_marker)
        return env

    def _stop_stub_session(self, env):
        """The stream is detached on purpose and outlives the shell, which is
        the one process this test must clean up after itself."""
        subprocess.run(["bash", str(SESSION_SCRIPT), "stop", "video"],
                       env=env, capture_output=True, text=True, timeout=60)

    def test_the_preview_player_is_gone_after_every_way_the_session_ends(self):
        env = self._env()
        self.addCleanup(self._stop_stub_session, env)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=900", "--height=1000"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(_stop, weston)

        socket_path = Path(env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        self.assertTrue(socket_path.exists(), "headless weston never came up")

        # The control for the after-the-shell check below: a process this
        # driver started, still running when the shell's player must not be.
        # Without it, "the player is gone" is equally what a liveness test that
        # answers `False` for everything reports.
        control = subprocess.Popen(["sleep", "600"])
        self.addCleanup(_stop, control)

        # dbus-run-session, not the inherited bus: the fake busctl is the only
        # daemon this harness may see. Through the retry wrapper: the nested
        # bus has collapsed under a green harness before (all checks ok,
        # summary line lost) - the environment's failure, retried once.
        proc = nested_display.run_harness_with_bus_retry(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            env=env, cwd=str(ROOT), timeout=600,
            marker=f"[PhonePreviewLifetime] checks: {EXPECTED_CHECKS} failures: 0")
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[PhonePreviewLifetime] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        # ---- the fifth ending: the shell itself went away -------------------
        #
        # The harness exited with a preview deliberately still up and said so
        # in the line above, so this is a before-and-after rather than a
        # question about a player that may never have started.
        self.assertTrue(self.pidfile.exists(), f"the stub player wrote no pid:\n{output}")
        pid = int(self.pidfile.read_text().strip())
        self.assertGreater(pid, 0, "the stub player wrote no pid")

        deadline = time.monotonic() + 10
        while _alive(pid) and time.monotonic() < deadline:
            time.sleep(0.2)
        still_there = _alive(pid)
        if still_there:
            # Never leave a 900-second sleep behind on the maintainer's
            # machine, whatever the verdict is.
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        self.assertTrue(_alive(control.pid),
                        "the control process died too, so this measurement says "
                        "nothing about the player")
        self.assertFalse(still_there,
                         f"the preview player at pid {pid} outlived the shell that "
                         f"started it, with nothing left able to stop it:\n{output}")


if __name__ == "__main__":
    unittest.main()
