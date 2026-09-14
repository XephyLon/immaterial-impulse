#!/usr/bin/env python3
"""Local retrieval end to end, in a nested shell.

A probe folder is configured, AiRag.index() runs the script with the offline
embedder, `search_documents` through Ai.handleFunctionCall answers with the
matching passage in a labelled data block and queues citation sources, and
the Documents toggle rides the passages in the wire content while the bubble
keeps the typed text. Script-level behaviour is tests/test_ai_rag.py.
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "AiRagRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"
EXPECTED_CHECKS = 10


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class AiRagRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-ai-rag-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        (self.config_home / "immaterial-impulse").mkdir(parents=True)
        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        (self.config_home / "immaterial-impulse/config.json").write_text(json.dumps(config, indent=2))
        self.probe = self.home / "probe"
        self.probe.mkdir()
        (self.probe / "wayland.md").write_text("# Wayland\n\nA compositor draws every window into one framebuffer.\n")
        (self.probe / "recipes.txt").write_text("Pancakes: flour, milk, eggs. Whisk and fry.\n")
        (self.probe / ".env").write_text("TOKEN=secret\n")

    def test_retrieval_end_to_end(self):
        env = nested_display.start(self, "ai-rag")
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["IMI_AI_RAG_PROBE_DIR"] = str(self.probe)
        proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT),
                              env=env, capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        for line in output.splitlines():
            if "[AiRag]" in line:
                print(line.strip())
        failed = [line for line in output.splitlines() if "[AiRag]" in line and "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output[-4000:]}")
        self.assertIn(f"[AiRag] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output[-4000:]}")
        self.assertTrue((self.home / "state/quickshell/user/rag/index.sqlite").exists(),
                        "the index lives under the state dir, not beside the documents")


if __name__ == "__main__":
    unittest.main()
