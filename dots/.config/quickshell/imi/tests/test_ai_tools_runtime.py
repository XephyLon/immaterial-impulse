#!/usr/bin/env python3
"""The assistant's read-tier tools answer inside a real shell.

The static contract pins declarations and dispatch; this drives
Ai.handleFunctionCall in a nested shell the way a model's tool call arrives:
the synchronous tools answer at once, the file tools answer through the
fenced script (allowed file in a data block, dotfile refused, outside path
refused, listing hides dotfiles) and the chat continues afterwards.
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "AiToolsRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"
EXPECTED_CHECKS = 8


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class AiToolsRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-ai-tools-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        (self.config_home / "immaterial-impulse").mkdir(parents=True)
        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        (self.config_home / "immaterial-impulse/config.json").write_text(json.dumps(config, indent=2))
        self.probe = self.home / "probe"
        self.probe.mkdir()
        (self.probe / "note.md").write_text("# note\n\nprobe note body\n")
        (self.probe / ".secret").write_text("TOKEN=abc\n")

    def test_the_read_tier_answers_in_a_real_shell(self):
        env = nested_display.start(self, "ai-tools")
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["IMI_AI_TOOLS_PROBE_DIR"] = str(self.probe)
        proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT),
                              env=env, capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        for line in output.splitlines():
            if "[AiTools]" in line:
                print(line.strip())
        failed = [line for line in output.splitlines() if "[AiTools]" in line and "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output[-4000:]}")
        self.assertIn(f"[AiTools] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output[-4000:]}")


if __name__ == "__main__":
    unittest.main()
