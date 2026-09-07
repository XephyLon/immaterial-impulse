#!/usr/bin/env python3
"""A rewritten colors.json reaches Appearance promptly and animated.

MaterialThemeLoader used to apply every palette after startup from a fixed
20 ms timer that read the FileView's text() before the asynchronous reload
had finished - so the previous palette was applied and the new one waited
for the next trigger - and it applied with animated=false, so a wallpaper
switch snapped instead of transitioning. It now applies on the FileView's
loaded() signal, animated after the first apply. This launches the shell's
theme loader against a throwaway state dir, rewrites colors.json the way
matugen does (truncate, then write) and watches the role follow.
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "ThemeReloadRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"
EXPECTED_CHECKS = 3


def _runtime_available():
    return nested_display.available()


@unittest.skipUnless(_runtime_available(),
                     "needs qs, weston and dbus-run-session on PATH")
class ThemeReloadRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-theme-reload-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        (self.config_home / "immaterial-impulse").mkdir(parents=True)
        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        (self.config_home / "immaterial-impulse/config.json").write_text(json.dumps(config, indent=2))
        generated = self.home / "state/quickshell/user/generated"
        generated.mkdir(parents=True)
        (generated / "colors.json").write_text(json.dumps({"primary": "#202020", "background": "#101010"}))

    def test_a_rewritten_palette_lands_promptly_and_animated(self):
        env = nested_display.start(self, "theme-reload")
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT),
                              env=env, capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        # The measured numbers belong in the suite log, not only in a failure.
        for line in output.splitlines():
            if "[ThemeReload]" in line:
                print(line.strip())
        failed = [line for line in output.splitlines() if "[ThemeReload]" in line and "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[ThemeReload] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")


if __name__ == "__main__":
    unittest.main()
