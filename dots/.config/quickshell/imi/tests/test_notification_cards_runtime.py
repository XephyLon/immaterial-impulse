#!/usr/bin/env python3
"""Drives two real notifications past the popup's card list, with the window
going down in between.

`NotificationCardsRuntimeTest.qml` builds the real `NotificationListView` in a
window bound to `Notifications.popupList` exactly as `NotificationPopup` binds
its layer surface. This module is the driver: headless weston, an isolated
D-Bus session so the harness's own notification server is the one `notify-send`
reaches, throwaway XDG dirs, and a short notification timeout so the first
popup goes away on its own.

Why a driver rather than a unit test: the list's card set is what the popup
hands to `WindowBlurRegion`, a stale entry publishes an empty region, and an
empty region is indistinguishable from a correct one everywhere except on
screen. The failure it guards ran for the whole life of the feature - every
notification after the first was unblurred - because the refresh observed the
model count, which does not move across a hide/show cycle from the same app.

Skips when weston, qs, notify-send or dbus-run-session are missing, as in CI.
"""

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "NotificationCardsRuntimeTest.qml"
SOCKET = "wayland-imi-notif-cards"
CONFIG = ('{"notifications":{"timeout":1500},'
          '"appearance":{"transparency":{"enable":true}}}')


# The harness prints how many checks it ran. This number is a literal rather
# than anything read back from that output: a harness whose step list shrinks
# must redden here instead of reporting `failures: 0` for a shorter run.
EXPECTED_CHECKS = 5


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def _runtime_available():
    return all(shutil.which(binary) is not None
               for binary in ("qs", "weston", "notify-send", "dbus-run-session"))


@unittest.skipUnless(_runtime_available(),
                     "needs qs, weston, notify-send and dbus-run-session on PATH")
class NotificationCardsRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-notif-cards-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_every_popup_publishes_the_card_that_is_on_screen(self):
        env = dict(os.environ)
        env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=900", "--height=700"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(_stop, weston)

        socket_path = Path(env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        self.assertTrue(socket_path.exists(), "headless weston never came up")

        # This box's headless EGL has no driver, so force software rendering.
        env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        env["QT_QUICK_BACKEND"] = "software"
        env["XDG_CONFIG_HOME"] = str(self.home / "config")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        shell_config = Path(env["XDG_CONFIG_HOME"]) / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        (shell_config / "config.json").write_text(CONFIG)

        # The harness owns org.freedesktop.Notifications on this bus, so the
        # notify-send calls below have to run on the same one - and must not
        # reach the caller's real notification daemon.
        script = self.home / "drive.sh"
        script.write_text(
            "#!/bin/bash\n"
            f'cd "{ROOT}"\n'
            "qs -p '%s' > '%s' 2>&1 &\n"
            "QS=$!\n"
            "sleep 6\n"
            "notify-send 'Cards probe' 'first popup'\n"
            "sleep 6\n"
            "notify-send 'Cards probe' 'second popup'\n"
            "sleep 8\n"
            "kill $QS 2>/dev/null\n"
            "wait $QS 2>/dev/null\n" % (HARNESS, self.home / "harness.log"))
        script.chmod(0o755)

        subprocess.run(["dbus-run-session", "--", str(script)],
                       cwd=str(ROOT), env=env, capture_output=True,
                       text=True, timeout=180)

        output = (self.home / "harness.log").read_text(errors="ignore")
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[NotifCards] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness never reached a verdict:\n{output}")


if __name__ == "__main__":
    unittest.main()
