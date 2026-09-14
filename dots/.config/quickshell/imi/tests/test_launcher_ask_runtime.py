#!/usr/bin/env python3
"""The launcher's Ask row behaves in a real shell.

No usable model: no row. A keyless probe model injected the way discovery
injects one: the row under the prefix, first, carrying the question without
the prefix; a long unmatched query gets it only with fallthrough on and a
short one never; nothing is sent while typing; askAssistant opens the
Intelligence tab and sends exactly the question.
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "LauncherAskRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"
EXPECTED_CHECKS = 10


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class LauncherAskRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-launcher-ask-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        (self.config_home / "immaterial-impulse").mkdir(parents=True)
        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        (self.config_home / "immaterial-impulse/config.json").write_text(json.dumps(config, indent=2))

    def test_the_ask_row_in_a_real_shell(self):
        env = nested_display.start(self, "launcher-ask")
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT),
                              env=env, capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        for line in output.splitlines():
            if "[LauncherAsk]" in line:
                print(line.strip())
        failed = [line for line in output.splitlines() if "[LauncherAsk]" in line and "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output[-4000:]}")
        self.assertIn(f"[LauncherAsk] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output[-4000:]}")


if __name__ == "__main__":
    unittest.main()
