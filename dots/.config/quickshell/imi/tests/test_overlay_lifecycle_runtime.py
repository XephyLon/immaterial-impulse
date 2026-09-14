#!/usr/bin/env python3
"""OverlayLifecycle against the real motion catalogue, in a nested shell.

Open: alive at once, progress from near 0 to 1 within the enter tier. Close:
alive holds while progress falls, closed() fires and only then alive drops,
within the exit tier. A close during the enter still ends closed; a re-open
during the leave keeps the surface; reduce-motion completes both at once and
still fires. The static half (hosts bind active: to .alive and gate their
mask on the flag) is tests/lint_overlay_lifecycle.py.
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "OverlayLifecycleRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"
EXPECTED_CHECKS = 15


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class OverlayLifecycleRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-overlay-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        (self.config_home / "immaterial-impulse").mkdir(parents=True)
        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        (self.config_home / "immaterial-impulse/config.json").write_text(json.dumps(config, indent=2))

    def test_the_lifecycle_in_a_real_shell(self):
        env = nested_display.start(self, "overlay-lifecycle")
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT),
                              env=env, capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        for line in output.splitlines():
            if "[Overlay]" in line:
                print(line.strip())
        failed = [line for line in output.splitlines() if "[Overlay]" in line and "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output[-4000:]}")
        self.assertIn(f"[Overlay] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output[-4000:]}")


if __name__ == "__main__":
    unittest.main()
