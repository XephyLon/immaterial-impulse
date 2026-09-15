#!/usr/bin/env python3
"""A fake of the Google endpoints the shell speaks to, for the runtime harness.

    fake_google_api.py <port>

Serves the OAuth token endpoint (POST /token), the Calendar list and events,
the Tasks lists and tasks (with POST / PATCH / DELETE), the Gmail INBOX label,
and userinfo. State is in memory; a bearer token other than "at-fake" is a
401. Every request is appended to /tmp-style log lines on stderr.
"""
import http.server
import json
import sys
import urllib.parse

STATE = {
    "tasks": {
        "L1": [
            {"id": "t1", "title": "Buy milk", "status": "needsAction", "position": "00000000000000000001"},
            {"id": "t2", "title": "Call the bank", "status": "needsAction", "position": "00000000000000000002", "due": "2026-09-20T00:00:00.000Z"},
        ]
    },
    "next_task": 3,
}


class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _authed(self):
        return self.headers.get("Authorization") == "Bearer at-fake"

    def _body(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode() if length else ""
        return raw

    def do_POST(self):  # noqa: N802
        path = urllib.parse.urlparse(self.path).path
        if path == "/token":
            form = urllib.parse.parse_qs(self._body())
            if form.get("refresh_token") == ["rt-fake"]:
                return self._send(200, {"access_token": "at-fake", "expires_in": 3600})
            return self._send(400, {"error": "invalid_grant"})
        if not self._authed():
            return self._send(401, {"error": {"code": 401, "message": "Invalid Credentials"}})
        m = path.split("/")
        if len(m) == 6 and m[1:4] == ["tasks", "v1", "lists"] and m[5] == "tasks":
            body = json.loads(self._body() or "{}")
            task = {"id": f"t{STATE['next_task']}", "title": body.get("title", ""), "status": "needsAction",
                    "position": f"{STATE['next_task']:020d}"}
            STATE["next_task"] += 1
            STATE["tasks"].setdefault(m[4], []).append(task)
            return self._send(200, task)
        return self._send(404, {"error": {"code": 404, "message": "not found"}})

    def do_PATCH(self):  # noqa: N802
        if not self._authed():
            return self._send(401, {"error": {"code": 401, "message": "Invalid Credentials"}})
        m = urllib.parse.urlparse(self.path).path.split("/")
        if len(m) == 7 and m[5] == "tasks":
            body = json.loads(self._body() or "{}")
            for t in STATE["tasks"].get(m[4], []):
                if t["id"] == m[6]:
                    t.update(body)
                    return self._send(200, t)
        return self._send(404, {"error": {"code": 404, "message": "not found"}})

    def do_DELETE(self):  # noqa: N802
        if not self._authed():
            return self._send(401, {"error": {"code": 401, "message": "Invalid Credentials"}})
        m = urllib.parse.urlparse(self.path).path.split("/")
        if len(m) == 7 and m[5] == "tasks":
            STATE["tasks"][m[4]] = [t for t in STATE["tasks"].get(m[4], []) if t["id"] != m[6]]
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        return self._send(404, {"error": {"code": 404, "message": "not found"}})

    def do_GET(self):  # noqa: N802
        url = urllib.parse.urlparse(self.path)
        path = url.path
        if path == "/userinfo":
            return self._send(200, {"email": "probe@example.com"})
        if not self._authed():
            return self._send(401, {"error": {"code": 401, "message": "Invalid Credentials"}})
        if path == "/calendar/v3/users/me/calendarList":
            return self._send(200, {"items": [
                {"id": "primary@example.com", "summary": "Probe", "primary": True, "selected": True, "backgroundColor": "#9fc6e7"},
                {"id": "hidden@example.com", "summary": "Hidden", "hidden": True},
            ]})
        if path.startswith("/calendar/v3/calendars/") and path.endswith("/events"):
            q = urllib.parse.parse_qs(url.query)
            start = q.get("timeMin", ["2026-01-01T00:00:00Z"])[0][:10]
            return self._send(200, {"items": [
                {"id": "e1", "summary": "Standup", "start": {"dateTime": start + "T09:30:00Z"}, "end": {"dateTime": start + "T09:45:00Z"}},
                {"id": "e2", "summary": "Day off", "start": {"date": start}, "end": {"date": start}},
                {"id": "e3", "summary": "Cancelled", "status": "cancelled", "start": {"date": start}},
            ]})
        if path == "/tasks/v1/users/@me/lists":
            return self._send(200, {"items": [{"id": "L1", "title": "My Tasks"}]})
        if path.startswith("/tasks/v1/lists/") and path.endswith("/tasks"):
            list_id = path.split("/")[4]
            items = [t for t in STATE["tasks"].get(list_id, []) if t["status"] != "completed"]
            return self._send(200, {"items": items})
        if path == "/gmail/v1/users/me/labels/INBOX":
            return self._send(200, {"id": "INBOX", "messagesUnread": 4, "threadsUnread": 3})
        return self._send(404, {"error": {"code": 404, "message": "not found"}})

    def log_message(self, fmt, *args):
        sys.stderr.write("[fake-google] " + (fmt % args) + "\n")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
