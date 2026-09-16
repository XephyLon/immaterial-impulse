#!/usr/bin/env python3
"""A fake OpenAI-compatible server for sandbox reviews: GET /v1/models lists
one model; POST /v1/chat/completions streams a plausible answer. Port from
argv[1] (default 18080). Logs each request's user text to stderr."""
import json, sys, time, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
ANSWERS = {
    "wayland compositor": "A Wayland compositor is the display server that composes every window and hands input straight to them.",
    "rotate": "Set transform on the monitor line in hyprland.conf: monitor=DP-1,preferred,auto,1,transform,1.",
    "default": "Short version: it depends on the setup, but the usual answer is yes, with one caveat about permissions.",
}
LONG = "This is a deliberately long reply that keeps going well past the two hundred character mark so that the cut and the ellipsis can be seen in the row, and it keeps going a little more for good measure. " * 2

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_HEAD(self):
        # The ollama CLI's heartbeat before any call.
        print("[fake] HEAD", self.path, file=sys.stderr, flush=True)
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()
    def do_GET(self):
        print(f"[fake] GET {self.path}", file=sys.stderr, flush=True)
        if self.path == "/":
            body = b"Ollama is running"; self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body); return
        if self.path.startswith("/api/version"):
            return self._json(200, {"version": "0.12.0"})
        if self.path.startswith("/api/tags"):
            # Ollama's listing, as `ollama list` (and the shell's discovery script) read it.
            return self._json(200, {"models": [{"name": "probe:latest", "model": "probe:latest", "modified_at": "2026-09-15T00:00:00Z",
                "size": 1000000, "digest": "0" * 64, "details": {"family": "probe", "parameter_size": "1B", "quantization_level": "Q4"}}]})
        if self.path.startswith("/api/ps"):
            return self._json(200, {"models": []})
        if self.path.rstrip("/").endswith("/models"):
            return self._json(200, {"object": "list", "data": [{"id": "probe-1", "object": "model", "owned_by": "sandbox"}]})
        self._json(404, {"error": {"message": "no"}})
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        req = json.loads(self.rfile.read(n) or b"{}")
        user = " ".join(m.get("content", "") if isinstance(m.get("content"), str) else "" for m in req.get("messages", []) if m.get("role") == "user")
        system = " ".join(m.get("content", "") for m in req.get("messages", []) if m.get("role") == "system")
        print(f"[fake] inline={'one short sentence' in system} user={user[:80]!r}", file=sys.stderr, flush=True)
        text = LONG if "long" in user.lower() else next((v for k, v in ANSWERS.items() if k in user.lower()), ANSWERS["default"])
        if "one short sentence" not in system:
            text = "**Sure.** " + text + "\n\nAnything else?"
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
        words = text.split(" ")
        for i in range(0, len(words), 2):
            chunk = " ".join(words[i:i + 2]) + (" " if i + 2 < len(words) else "")
            try:
                self.wfile.write(f"data: {json.dumps({'choices': [{'delta': {'content': chunk}}]})}\n\n".encode()); self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError): return
            time.sleep(0.06)
        try: self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError): pass

srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
print(f"[fake] listening on {PORT}", file=sys.stderr, flush=True)
srv.serve_forever()
