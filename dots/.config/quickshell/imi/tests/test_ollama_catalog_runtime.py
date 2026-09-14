#!/usr/bin/env python3
"""OllamaCatalog against a fake daemon, inside a real shell.

A tiny HTTP server plays Ollama: /api/tags lists two installed models,
/api/ps one loaded, /api/pull streams the daemon's NDJSON status lines with
byte counts and then records the model as installed, /api/delete forgets it.
The harness watches the service follow: lists, progress to 1, the pulled
model installed and known to the chat, the removal both places. Discovery
(Ai.qml's show-installed-ollama-models.sh) is pointed at a stub `ollama` on
PATH that lists the fake's models.
"""
import json
import os
import shutil
import stat
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "OllamaCatalogRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"
EXPECTED_CHECKS = 15


class FakeOllama(BaseHTTPRequestHandler):
    installed = {}      # name -> record
    loaded = ["llama3.2:3b"]
    lock = threading.Lock()

    def log_message(self, *args):
        pass

    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/tags":
            with self.lock:
                models = list(self.installed.values())
            return self._json(200, {"models": models})
        if self.path == "/api/ps":
            return self._json(200, {"models": [{"name": n, "model": n} for n in self.loaded]})
        self._json(404, {"error": "no"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        req = json.loads(self.rfile.read(length) or b"{}")
        if self.path == "/api/pull":
            name = req.get("model") or req.get("name")
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            events = [{"status": "pulling manifest"},
                      {"status": "pulling sha256:abc", "digest": "sha256:abc", "total": 1000, "completed": 250},
                      {"status": "pulling sha256:abc", "digest": "sha256:abc", "total": 1000, "completed": 1000},
                      {"status": "verifying sha256 digest"},
                      {"status": "writing manifest"},
                      {"status": "success"}]
            for e in events:
                chunk = (json.dumps(e) + "\n").encode()
                self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
                self.wfile.flush()
                time.sleep(0.15)
            with self.lock:
                self.installed[name] = {"name": name, "model": name, "size": 5200000000,
                                        "details": {"family": "qwen3", "parameter_size": "8.2B", "quantization_level": "Q4_K_M"}}
            self.wfile.write(b"0\r\n\r\n")
            return
        self._json(404, {"error": "no"})

    def do_DELETE(self):
        length = int(self.headers.get("Content-Length", "0"))
        req = json.loads(self.rfile.read(length) or b"{}")
        name = req.get("model") or req.get("name")
        with self.lock:
            existed = self.installed.pop(name, None) is not None
        self.send_response(200 if existed else 404)
        self.send_header("Content-Length", "0")
        self.end_headers()


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class OllamaCatalogRuntimeTest(unittest.TestCase):
    def setUp(self):
        FakeOllama.installed = {
            "llama3.2:3b": {"name": "llama3.2:3b", "model": "llama3.2:3b", "size": 2019393189,
                            "details": {"family": "llama", "parameter_size": "3.2B", "quantization_level": "Q4_K_M"}},
            "nomic-embed-text:latest": {"name": "nomic-embed-text:latest", "model": "nomic-embed-text:latest", "size": 274302450,
                                        "details": {"family": "nomic-bert", "parameter_size": "137M", "quantization_level": "F16"}},
        }
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeOllama)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.shutdown)

        self.home = Path(tempfile.mkdtemp(prefix="imi-ollama-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        (self.config_home / "immaterial-impulse").mkdir(parents=True)
        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        (self.config_home / "immaterial-impulse/config.json").write_text(json.dumps(config, indent=2))
        # Discovery still shells out to `ollama list`; a stub answers with the
        # fake daemon's current list so the chat's model list follows a pull.
        self.bin = self.home / "bin"
        self.bin.mkdir()
        stub = self.bin / "ollama"
        stub.write_text("#!/bin/sh\n"
                        "printf 'NAME ID SIZE MODIFIED\\n'\n"
                        f"curl -sf http://127.0.0.1:{self.port}/api/tags | python3 -c "
                        "'import json,sys; [print(m[\"name\"], \"x\", \"1 GB\", \"now\") for m in json.load(sys.stdin)[\"models\"]]'\n")
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)

    def test_the_catalog_follows_a_fake_daemon(self):
        env = nested_display.start(self, "ollama-catalog")
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["IMI_OLLAMA_URL"] = f"http://127.0.0.1:{self.port}"
        env["PATH"] = f"{self.bin}:{env.get('PATH', os.environ['PATH'])}"
        proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT),
                              env=env, capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        for line in output.splitlines():
            if "[OllamaCatalog]" in line:
                print(line.strip())
        failed = [line for line in output.splitlines() if "[OllamaCatalog]" in line and "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output[-4000:]}")
        self.assertIn(f"[OllamaCatalog] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output[-4000:]}")


if __name__ == "__main__":
    unittest.main()
