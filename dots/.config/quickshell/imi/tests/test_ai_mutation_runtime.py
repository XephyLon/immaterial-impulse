#!/usr/bin/env python3
"""The reviewed tier end to end, in a nested shell.

A reviewed tool call raises the approval card and changes nothing; reject
answers the model and changes nothing; approve applies it (a to-do, a file
with its .bak, a palette source) and answers; an invalid call is refused
without a card; a write outside the allowlist is refused by the fence even
when approved. Static half: tests/test_ai_mutation_tier.py.
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "AiMutationRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"
EXPECTED_CHECKS = 8


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class AiMutationRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-ai-mutation-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        (self.config_home / "immaterial-impulse").mkdir(parents=True)
        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        (self.config_home / "immaterial-impulse/config.json").write_text(json.dumps(config, indent=2))
        self.probe = self.home / "probe"
        self.probe.mkdir()
        (self.probe / "note.md").write_text("original\n")

    def test_the_reviewed_tier_in_a_real_shell(self):
        env = nested_display.start(self, "ai-mutation")
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["IMI_AI_MUTATION_PROBE_DIR"] = str(self.probe)
        proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT),
                              env=env, capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        for line in output.splitlines():
            if "[Mutation]" in line:
                print(line.strip())
        failed = [line for line in output.splitlines() if "[Mutation]" in line and "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output[-4000:]}")
        self.assertIn(f"[Mutation] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output[-4000:]}")
        self.assertEqual((self.probe / "note.md").read_text(), "rewritten by the assistant\n")
        self.assertEqual((self.probe / "note.md.bak").read_text(), "original\n")


if __name__ == "__main__":
    unittest.main()
