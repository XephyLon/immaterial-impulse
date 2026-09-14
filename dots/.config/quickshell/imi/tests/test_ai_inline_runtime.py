#!/usr/bin/env python3
"""Inline launcher answers end to end, against a fake OpenAI-compatible server.

The harness (AiInlineRuntimeTest.qml) drives the launcher in a nested shell;
this side serves the streaming replies and counts what arrived: one request
per pause (a burst of keystrokes is one request), every request with the
one-sentence system prompt, the question alone, no tools; nothing for the
short question, nothing for the remote model until the cloud switch.
"""
import json
import shutil
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "AiInlineRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"
EXPECTED_CHECKS = 16
SHORT = "A Wayland compositor is the display server that draws every window itself."
LONG = "This answer is long on purpose. " * 12


class FakeChat(BaseHTTPRequestHandler):
    requests = []
    lock = threading.Lock()

    def log_message(self, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        req = json.loads(self.rfile.read(length) or b"{}")
        with self.lock:
            self.requests.append(req)
        question = " ".join(m.get("content", "") for m in req.get("messages", []) if m.get("role") == "user")
        text = LONG if "longwinded" in question else SHORT
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        words = text.split(" ")
        for i in range(0, len(words), 3):
            chunk = " ".join(words[i:i + 3]) + (" " if i + 3 < len(words) else "")
            frame = {"choices": [{"delta": {"content": chunk}}]}
            try:
                self.wfile.write(f"data: {json.dumps(frame)}\n\n".encode())
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                return
            time.sleep(0.02)
        try:
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class AiInlineRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-ai-inline-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        (self.config_home / "immaterial-impulse").mkdir(parents=True)
        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        (self.config_home / "immaterial-impulse/config.json").write_text(json.dumps(config, indent=2))
        FakeChat.requests = []
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeChat)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.shutdown)

    def test_inline_answers_in_a_real_shell(self):
        env = nested_display.start(self, "ai-inline")
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["IMI_AI_INLINE_PROBE_URL"] = f"http://127.0.0.1:{self.server.server_address[1]}/v1/chat/completions"
        proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT),
                              env=env, capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        for line in output.splitlines():
            if "[AiInline]" in line:
                print(line.strip())
        failed = [line for line in output.splitlines() if "[AiInline]" in line and "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output[-4000:]}")
        self.assertIn(f"[AiInline] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output[-4000:]}")
        # Three pauses reached the server: the first question, the long one,
        # the one Enter carried into the chat. The short question, the
        # inline-off typing and the remote-model typing sent nothing here.
        questions = [" ".join(m["content"] for m in r["messages"] if m["role"] == "user") for r in FakeChat.requests]
        self.assertEqual(questions, ["what is a wayland compositor", "tell me something longwinded please",
                                     "what is a wayland compositor"], questions)
        for req in FakeChat.requests:
            system = [m for m in req["messages"] if m["role"] == "system"]
            self.assertEqual(len(system), 1)
            self.assertIn("one short sentence", system[0]["content"])
            self.assertEqual(len(req["messages"]), 2, "the question alone: no chat history rides along")
            self.assertEqual(req.get("tools", []), [], "no tools on an inline request")
            self.assertTrue(req.get("stream"))


if __name__ == "__main__":
    unittest.main()
