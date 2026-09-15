#!/usr/bin/env python3
"""scripts/accounts/google_oauth.py against a fake token endpoint.

The helper takes its secrets from the environment (never argv), refreshes an
access token through a POST form, and reports failures as one JSON line with
a non-zero exit. The interactive `authorize` flow is driven end to end with
the browser replaced by a thread that follows the printed URL's redirect.
"""
import base64
import hashlib
import http.server
import json
import os
import re
import subprocess
import sys
import threading
import unittest
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/accounts/google_oauth.py"


class FakeGoogle(http.server.BaseHTTPRequestHandler):
    tokens_seen = []
    # The S256 challenge the consent URL advertised; the code exchange must
    # carry the verifier that hashes to it, as Google's endpoint checks.
    expected_challenge = None

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        form = urllib.parse.parse_qs(self.rfile.read(length).decode())
        FakeGoogle.tokens_seen.append(form)
        if form.get("grant_type") == ["refresh_token"]:
            if form.get("refresh_token") == ["good-refresh"]:
                body = {"access_token": "at-123", "expires_in": 3599}
                code = 200
            else:
                body = {"error": "invalid_grant", "error_description": "Token has been revoked."}
                code = 400
        else:
            verifier = (form.get("code_verifier") or [""])[0]
            digest = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
            ok = bool(verifier) and digest == FakeGoogle.expected_challenge
            body = {"access_token": "at-first", "refresh_token": "rt-new"} if ok else {"error": "invalid_grant", "error_description": "PKCE mismatch"}
            code = 200 if ok else 400
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802
        data = json.dumps({"email": "someone@example.com"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        return


class GoogleOauthHelper(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeGoogle)
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def run_helper(self, *args, env=None, timeout=20):
        full = {"PATH": os.environ["PATH"], "IMI_GOOGLE_OAUTH_BASE": self.base, "IMI_GOOGLE_USERINFO_URL": self.base + "/userinfo"}
        full.update(env or {})
        return subprocess.run([sys.executable, str(HELPER), *args], env=full, capture_output=True, text=True, timeout=timeout)

    def test_refresh_prints_the_access_token(self):
        r = self.run_helper("refresh", env={"GOOGLE_CLIENT_ID": "cid", "GOOGLE_CLIENT_SECRET": "sec", "GOOGLE_REFRESH_TOKEN": "good-refresh"})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout), {"access_token": "at-123", "expires_in": 3599})
        self.assertEqual(FakeGoogle.tokens_seen[-1]["client_secret"], ["sec"])

    def test_a_revoked_token_is_one_json_error_line(self):
        r = self.run_helper("refresh", env={"GOOGLE_CLIENT_ID": "cid", "GOOGLE_CLIENT_SECRET": "sec", "GOOGLE_REFRESH_TOKEN": "revoked"})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("revoked", json.loads(r.stdout)["error"])

    def test_missing_secrets_fail_before_any_request(self):
        before = len(FakeGoogle.tokens_seen)
        r = self.run_helper("refresh", env={"GOOGLE_CLIENT_ID": "cid"})
        self.assertEqual(r.returncode, 2)
        self.assertIn("GOOGLE_CLIENT_SECRET", json.loads(r.stdout)["error"])
        self.assertEqual(len(FakeGoogle.tokens_seen), before)

    def test_no_secret_ever_appears_in_argv(self):
        source = HELPER.read_text()
        self.assertIn('os.environ.get("GOOGLE_CLIENT_SECRET"', source)
        self.assertIn('os.environ.get("GOOGLE_REFRESH_TOKEN"', source)
        # The shell's side: the helper's command arrays hold the two verbs and nothing else.
        account = (ROOT / "services/GoogleAccount.qml").read_text()
        self.assertEqual(re.findall(r'command: \[[^\]]*helperPath[^\]]*\]', account),
                         ['command: ["python3", root.helperPath, "authorize"]', 'command: ["python3", root.helperPath, "refresh"]'])
        self.assertIn("environment: root.helperEnv", account)

    def test_a_redirect_with_the_wrong_state_is_refused(self):
        env = {"PATH": os.environ["PATH"], "IMI_GOOGLE_OAUTH_BASE": self.base, "IMI_GOOGLE_AUTH_URL": self.base + "/auth",
               "IMI_NO_BROWSER": "1", "IMI_OAUTH_TIMEOUT": "15", "GOOGLE_CLIENT_ID": "cid", "GOOGLE_CLIENT_SECRET": "sec"}
        proc = subprocess.Popen([sys.executable, str(HELPER), "authorize"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        url = json.loads(proc.stderr.readline())["open"]
        query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
        before = len(FakeGoogle.tokens_seen)
        urllib.request.urlopen(query["redirect_uri"][0] + "?" + urllib.parse.urlencode({"code": "abc", "state": "forged"}), timeout=10).read()
        out, err = proc.communicate(timeout=20)
        self.assertEqual(proc.returncode, 4, out)
        self.assertIn("state", json.loads(out)["error"])
        self.assertEqual(len(FakeGoogle.tokens_seen), before, "no code exchange after a forged state")

    def test_authorize_round_trips_through_the_loopback_redirect(self):
        env = {"PATH": os.environ["PATH"], "IMI_GOOGLE_OAUTH_BASE": self.base, "IMI_GOOGLE_USERINFO_URL": self.base + "/userinfo",
               "IMI_GOOGLE_AUTH_URL": self.base + "/auth", "IMI_NO_BROWSER": "1", "IMI_OAUTH_TIMEOUT": "15",
               "GOOGLE_CLIENT_ID": "cid", "GOOGLE_CLIENT_SECRET": "sec"}
        proc = subprocess.Popen([sys.executable, str(HELPER), "authorize"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        # The helper prints the consent URL on stderr when it may not open a browser;
        # a "user" follows it by hitting the redirect_uri with a code and the state.
        line = proc.stderr.readline()
        url = json.loads(line)["open"]
        query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
        self.assertEqual(query["code_challenge_method"], ["S256"])
        self.assertEqual(query["access_type"], ["offline"])
        self.assertIn("calendar.readonly", query["scope"][0])
        redirect = query["redirect_uri"][0]
        self.assertTrue(redirect.startswith("http://127.0.0.1:"))
        FakeGoogle.expected_challenge = query["code_challenge"][0]
        urllib.request.urlopen(redirect + "?" + urllib.parse.urlencode({"code": "abc", "state": query["state"][0]}), timeout=10).read()
        out, err = proc.communicate(timeout=20)
        self.assertEqual(proc.returncode, 0, err)
        self.assertEqual(json.loads(out), {"refresh_token": "rt-new", "email": "someone@example.com"})


if __name__ == "__main__":
    unittest.main()
