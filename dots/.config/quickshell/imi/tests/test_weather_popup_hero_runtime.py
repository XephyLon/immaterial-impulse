#!/usr/bin/env python3
"""Drives the weather popup with its hourly row in it, in a real window.

`WeatherPopupHeroRuntimeTest.qml` builds the real `WeatherPopup`, parents its
content into a window the way `BarPopupOverlay` parents it into the card, seeds
`Weather.hourly`, and measures two things nothing else can see.

The card opens at the height of the content's FIRST DRAWN section and unfurls
from there, so a section added to a popup silently changes what the popup opens
at unless it lands after the hero - and `heroSectionHeight` skips undrawn and
zero-height children, so which section that is, is a fact about the built tree
rather than about the source order. A row that became the hero would open the
weather card as a 60px strip with the temperature and the city below the fold.

And the bars grow from the axis on the popup's own visibility, which is what
makes the motion play on a REFRESH as well as on an open. The tree this was
taken from writes its bar heights from a NumberAnimation that destroys the
binding, so its chart animates on open and never on data
(docs/p3drovfx-animation-research-2026-08-16.md §3.3). A settled height is the
same number whether it animated or teleported, so the harness samples the bars
in flight and compares the samples afterwards.

Headless weston and a private bus, never the caller's session: this launches a
`qs` and none of it may reach the user's compositor or their shell.

Skips when weston, qs or dbus-run-session are missing, as in CI.
"""

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "WeatherPopupHeroRuntimeTest.qml"
SOCKET = "wayland-imi-weather-hero"

# The harness prints how many checks it ran. A literal rather than anything
# read back out of its own output: a step that stops being reached must redden
# here instead of reporting `failures: 0` for a shorter run.
EXPECTED_CHECKS = 11


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def _runtime_available():
    return all(shutil.which(binary) is not None
               for binary in ("qs", "weston", "dbus-run-session"))


@unittest.skipUnless(_runtime_available(),
                     "needs qs, weston and dbus-run-session on PATH")
class WeatherPopupHeroRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-weather-hero-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_the_hourly_row_lands_after_the_hero_and_its_bars_grow(self):
        env = dict(os.environ)
        env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)
        # Nothing here may reach the user's compositor; hyprctl and anything
        # else keyed on the signature would, whatever the wayland socket says.
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=900", "--height=900"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(_stop, weston)

        socket_path = Path(env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        self.assertTrue(socket_path.exists(), "headless weston never came up")

        env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        env["QT_QUICK_BACKEND"] = "software"
        env["XDG_CONFIG_HOME"] = str(self.home / "config")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        for key in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME"):
            Path(env[key]).mkdir(parents=True, exist_ok=True)

        proc = subprocess.run(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=180)

        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[WeatherHero] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness never reached a verdict:\n{output}")


if __name__ == "__main__":
    unittest.main()
