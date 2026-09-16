#!/usr/bin/env python3
"""Google OAuth 2.0 for an installed app, standard library only.

  google_oauth.py authorize   opens the consent page in the browser, listens on a
                              loopback port for the redirect, exchanges the code
                              (PKCE) and prints {"refresh_token", "email"}.
  google_oauth.py refresh     prints {"access_token", "expires_in"}.

Secrets arrive in the environment, never on the command line:
  GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN (refresh only).
Optional: GOOGLE_SCOPES (space-separated), IMI_GOOGLE_OAUTH_BASE (the tests'
fake endpoint; default https://oauth2.googleapis.com), IMI_GOOGLE_AUTH_URL,
IMI_GOOGLE_USERINFO_URL, IMI_NO_BROWSER=1 (print the URL instead of opening it),
IMI_OAUTH_TIMEOUT (seconds to wait for the redirect, default 300).
Exit 0 with JSON on stdout, else a non-zero code with {"error": ...}.
"""
import base64
import hashlib
import http.server
import json
import os
import secrets
import subprocess
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request

OAUTH_BASE = os.environ.get("IMI_GOOGLE_OAUTH_BASE", "https://oauth2.googleapis.com").rstrip("/")
AUTH_URL = os.environ.get("IMI_GOOGLE_AUTH_URL", "https://accounts.google.com/o/oauth2/v2/auth")
USERINFO_URL = os.environ.get("IMI_GOOGLE_USERINFO_URL", "https://openidconnect.googleapis.com/v1/userinfo")
TOKEN_URL = OAUTH_BASE + "/token"
DEFAULT_SCOPES = " ".join([
    "openid",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/tasks",
    "https://www.googleapis.com/auth/gmail.readonly",
])


def fail(message, code=1):
    print(json.dumps({"error": message}))
    sys.exit(code)


def post_form(url, fields):
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        try:
            detail = json.loads(body)
            detail = detail.get("error_description") or detail.get("error") or body
        except ValueError:
            detail = body
        fail(f"{url.rsplit('/', 1)[-1]}: HTTP {e.code}: {detail}")
    except (urllib.error.URLError, TimeoutError) as e:
        fail(f"{url.rsplit('/', 1)[-1]}: {e}")


def get_json(url, token):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode() or "{}")
    except (urllib.error.URLError, TimeoutError, ValueError):
        return {}


def credentials():
    cid = os.environ.get("GOOGLE_CLIENT_ID", "").strip()
    secret = os.environ.get("GOOGLE_CLIENT_SECRET", "").strip()
    if not cid or not secret:
        fail("GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are required", 2)
    return cid, secret


class _Redirect(http.server.BaseHTTPRequestHandler):
    result = {}
    done = threading.Event()

    def do_GET(self):  # noqa: N802
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        _Redirect.result = {k: v[0] for k, v in query.items()}
        body = ("<html><body style='font-family:sans-serif'><h2>Connected.</h2>"
                "<p>You can close this tab and go back to the shell.</p></body></html>").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        _Redirect.done.set()

    def log_message(self, *args):  # quiet
        return


def authorize():
    cid, secret = credentials()
    scopes = os.environ.get("GOOGLE_SCOPES", DEFAULT_SCOPES)
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(48)).rstrip(b"=").decode()
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)

    server = http.server.HTTPServer(("127.0.0.1", 0), _Redirect)
    port = server.server_address[1]
    redirect = f"http://127.0.0.1:{port}/"
    thread = threading.Thread(target=server.handle_request, daemon=True)
    thread.start()

    params = {
        "client_id": cid, "redirect_uri": redirect, "response_type": "code", "scope": scopes,
        "access_type": "offline", "prompt": "consent", "state": state,
        "code_challenge": challenge, "code_challenge_method": "S256",
    }
    url = AUTH_URL + "?" + urllib.parse.urlencode(params)
    if os.environ.get("IMI_NO_BROWSER") == "1":
        print(json.dumps({"open": url}), file=sys.stderr, flush=True)
    else:
        try:
            subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            print(json.dumps({"open": url}), file=sys.stderr, flush=True)

    timeout = float(os.environ.get("IMI_OAUTH_TIMEOUT", "300"))
    if not _Redirect.done.wait(timeout):
        server.server_close()
        fail("timed out waiting for the sign-in to finish", 3)
    server.server_close()
    got = _Redirect.result
    if got.get("state") != state:
        fail("the redirect did not carry our state", 4)
    if "code" not in got:
        error = got.get("error", "no code in the redirect")
        # Google's consent page answers a Testing-status app with a bare
        # access_denied for any account that is not one of its test users;
        # the raw word told the user nothing about the fix.
        if error == "access_denied":
            error = ("Google refused the sign-in (access_denied). While the OAuth client is in "
                     "Testing, only its test users may sign in: add this Google account under "
                     "OAuth consent screen > Audience > Test users, then connect again.")
        fail(error, 4)

    tokens = post_form(TOKEN_URL, {
        "code": got["code"], "client_id": cid, "client_secret": secret,
        "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier,
    })
    refresh = tokens.get("refresh_token")
    if not refresh:
        fail("Google returned no refresh token (revoke the app's access and try again)", 5)
    email = get_json(USERINFO_URL, tokens.get("access_token", "")).get("email", "")
    print(json.dumps({"refresh_token": refresh, "email": email}))


def refresh():
    cid, secret = credentials()
    token = os.environ.get("GOOGLE_REFRESH_TOKEN", "").strip()
    if not token:
        fail("GOOGLE_REFRESH_TOKEN is required", 2)
    tokens = post_form(TOKEN_URL, {
        "client_id": cid, "client_secret": secret, "refresh_token": token, "grant_type": "refresh_token",
    })
    if "access_token" not in tokens:
        fail("no access token in the response", 5)
    print(json.dumps({"access_token": tokens["access_token"], "expires_in": int(tokens.get("expires_in", 3600))}))


def main(argv):
    if len(argv) != 2 or argv[1] not in ("authorize", "refresh"):
        fail("usage: google_oauth.py authorize|refresh", 2)
    (authorize if argv[1] == "authorize" else refresh)()


if __name__ == "__main__":
    main(sys.argv)
