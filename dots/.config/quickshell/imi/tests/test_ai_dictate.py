#!/usr/bin/env python3
"""scripts/ai/ai_dictate.py: the recording state machine, without a model.

A stub `pw-record` on PATH writes a WAV and waits for SIGINT the way the real
one does; IMI_DICTATE_FAKE_TRANSCRIPT stands in for the transcriber. Start
returns at once and records the pid; a second start is refused; stop ends
the recorder, returns the text and the seconds, and removes the take; stop
without start is a refusal, not a traceback; a missing transcriber names
what to install.
"""
import json
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/ai/ai_dictate.py"

STUB_RECORDER = """#!/bin/sh
# Writes a small (silent) WAV to the last argument, then waits for SIGINT.
# POSIX sh on purpose: CI's /bin/sh is dash, where ${@: -1} is a syntax error
# and the stub died before recording anything.
for out; do :; done
python3 - "$out" <<'PY'
import struct, sys, wave
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(b"\\x00\\x00" * 16000)
PY
trap 'exit 0' INT TERM
while :; do sleep 0.1; done
"""


class Dictate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bin = Path(self.tmp.name) / "bin"
        self.bin.mkdir()
        stub = self.bin / "pw-record"
        stub.write_text(STUB_RECORDER)
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        self.rt = Path(self.tmp.name) / "rt"
        self.rt.mkdir()

    def run_script(self, *argv, fake=None, with_recorder=True, extra_env=None):
        # Without the recorder the PATH is an empty dir: the real pw-record
        # lives in /usr/bin and would answer for the stub.
        empty = Path(self.tmp.name) / "emptybin"
        empty.mkdir(exist_ok=True)
        env = {"PATH": f"{self.bin}:/usr/bin:/bin" if with_recorder else str(empty),
               "HOME": os.environ["HOME"], "IMI_DICTATE_RUNTIME_DIR": str(self.rt),
               "IMMATERIAL_IMPULSE_VIRTUAL_ENV": str(Path(self.tmp.name) / "no-venv")}
        if fake is not None:
            env["IMI_DICTATE_FAKE_TRANSCRIPT"] = fake
        if extra_env:
            env.update(extra_env)
        out = subprocess.run([sys.executable, str(SCRIPT), *argv], env=env, capture_output=True, text=True, timeout=60)
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout.strip().splitlines()[-1])

    def test_probe_reports_what_is_there(self):
        p = self.run_script("probe")
        self.assertTrue(p["ok"])
        self.assertEqual(p["recorder"], "pw-record")
        for key in ("faster_whisper", "whisper_cli", "whisper_cpp_model"):
            self.assertIn(key, p)
        self.assertIsNone(self.run_script("probe", with_recorder=False)["recorder"])

    def test_start_stop_round_trip_with_the_fake_transcriber(self):
        self.assertFalse(self.run_script("status")["recording"])
        s = self.run_script("start")
        self.assertTrue(s["ok"], s)
        self.assertTrue(self.run_script("status")["recording"])
        again = self.run_script("start")
        self.assertFalse(again["ok"])
        self.assertIn("Already", again["error"])
        time.sleep(0.4)
        r = self.run_script("stop", fake="hello from the fake transcriber")
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["text"], "hello from the fake transcriber")
        self.assertEqual(r["engine"], "fake")
        self.assertGreater(r["seconds"], 0)
        self.assertFalse(list(self.rt.glob("imi-dictate/*.wav")), "the take is removed after transcription")
        self.assertFalse((self.rt / "imi-dictate/recording.json").exists())
        self.assertFalse(self.run_script("status")["recording"])

    def test_stop_without_start_is_a_refusal(self):
        r = self.run_script("stop")
        self.assertFalse(r["ok"])
        self.assertIn("Not recording", r["error"])

    def test_a_missing_transcriber_names_what_to_install(self):
        self.run_script("start")
        time.sleep(0.3)
        r = self.run_script("stop")   # no fake, no faster-whisper, no whisper-cli on this PATH
        self.assertFalse(r["ok"])
        self.assertIn("faster-whisper", r["error"])

    def test_provider_engine_needs_a_key(self):
        self.run_script("start")
        time.sleep(0.3)
        r = self.run_script("stop", "--engine", "provider")
        self.assertFalse(r["ok"])
        self.assertIn("API key", r["error"])

    def test_no_recorder_is_a_clear_error(self):
        r = self.run_script("start", with_recorder=False)
        self.assertFalse(r["ok"])
        self.assertIn("recorder", r["error"].lower())


if __name__ == "__main__":
    unittest.main()
