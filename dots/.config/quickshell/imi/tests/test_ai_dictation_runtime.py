#!/usr/bin/env python3
"""Dictation end to end, in a nested shell.

A stub `pw-record` on PATH and IMI_DICTATE_FAKE_TRANSCRIPT stand in for the
microphone and the model: start -> listening with a running clock, stop ->
transcribing -> idle with the text in the draft and the signal fired; a
second take appends; the watchdog stops a recording at maxSeconds; auto-send
sends instead of drafting. Script-level behaviour is tests/test_ai_dictate.py.
"""
import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

import nested_display
from test_ai_dictate import STUB_RECORDER

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "AiDictationRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"
EXPECTED_CHECKS = 12


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class AiDictationRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-dictation-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        (self.config_home / "immaterial-impulse").mkdir(parents=True)
        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        (self.config_home / "immaterial-impulse/config.json").write_text(json.dumps(config, indent=2))
        self.bin = self.home / "bin"
        self.bin.mkdir()
        stub = self.bin / "pw-record"
        stub.write_text(STUB_RECORDER)
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        (self.home / "rt").mkdir()

    def test_dictation_end_to_end(self):
        env = nested_display.start(self, "ai-dictation")
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["PATH"] = f"{self.bin}:{env.get('PATH', os.environ['PATH'])}"
        env["IMI_DICTATE_RUNTIME_DIR"] = str(self.home / "rt")
        env["IMI_DICTATE_FAKE_TRANSCRIPT"] = "hello from the fake transcriber"
        env["IMMATERIAL_IMPULSE_VIRTUAL_ENV"] = str(self.home / "no-venv")
        proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT),
                              env=env, capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        for line in output.splitlines():
            if "[Dictation]" in line:
                print(line.strip())
        failed = [line for line in output.splitlines() if "[Dictation]" in line and "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output[-4000:]}")
        self.assertIn(f"[Dictation] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output[-4000:]}")


if __name__ == "__main__":
    unittest.main()
