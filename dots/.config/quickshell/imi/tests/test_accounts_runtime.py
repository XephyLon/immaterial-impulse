#!/usr/bin/env python3
"""The Google account's services end to end, in a nested shell.

Against tests/fake_google_api.py: the helper turns the refresh token into an
access token, the calendar's events reach IcsCalendar, the tasks list and
its writes round-trip, the unread count lands, and disconnecting clears it
all. The keyring is a throwaway XDG home's own gnome-keyring is NOT used:
`secret-tool` is shadowed by a stub that keeps the blob in a file, so no
real keyring item is ever read or written. Static half:
tests/test_accounts_contract.py.
"""
import json
import os
import shutil
import socket
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "AccountsRuntimeTest.qml"
FAKE = ROOT / "tests/fake_google_api.py"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"
EXPECTED_CHECKS = 10

SECRET_TOOL_STUB = r'''#!/bin/sh
# A file-backed secret-tool: `store` reads the secret from stdin, `lookup`
# prints it (exit 1 when nothing was stored), `search` prints nothing.
f="$IMI_FAKE_SECRET_FILE"
case "$1" in
  store) cat > "$f" ;;
  lookup) [ -s "$f" ] && cat "$f" || exit 1 ;;
  *) exit 0 ;;
esac
'''


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class AccountsRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-accounts-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        (self.config_home / "immaterial-impulse").mkdir(parents=True)
        config = json.loads(SHIPPED_DEFAULT.read_text())
        config["migratedUpstreamSchema"] = True
        (self.config_home / "immaterial-impulse/config.json").write_text(json.dumps(config, indent=2))
        stub_dir = self.home / "bin"
        stub_dir.mkdir()
        stub = stub_dir / "secret-tool"
        stub.write_text(SECRET_TOOL_STUB)
        stub.chmod(0o755)
        self.stub_dir = stub_dir
        # An empty blob to start from: a missing item makes try_lookup.sh ask
        # the (absent) keyring daemon whether the collection is locked, and
        # KeyringStorage rightly refuses to fresh-init on that answer.
        (self.home / "secret.json").write_text("{}")
        self.port = free_port()
        self.fake = subprocess.Popen(["python3", str(FAKE), str(self.port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(self.fake.terminate)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            try:
                socket.create_connection(("127.0.0.1", self.port), timeout=0.5).close()
                break
            except OSError:
                time.sleep(0.1)

    def test_the_google_services_in_a_real_shell(self):
        env = nested_display.start(self, "accounts")
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["PATH"] = f"{self.stub_dir}:{env['PATH']}"
        env["IMI_FAKE_SECRET_FILE"] = str(self.home / "secret.json")
        base = f"http://127.0.0.1:{self.port}"
        env["IMI_GOOGLE_API_BASE"] = base
        env["IMI_GOOGLE_OAUTH_BASE"] = base
        env["IMI_GOOGLE_USERINFO_URL"] = base + "/userinfo"
        proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT),
                              env=env, capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        for line in output.splitlines():
            if "[AccountsRt]" in line:
                print(line.strip())
        failed = [line for line in output.splitlines() if "[AccountsRt]" in line and "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output[-4000:]}")
        self.assertIn(f"[AccountsRt] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output[-4000:]}")
        blob = json.loads((self.home / "secret.json").read_text())
        self.assertEqual(blob["google"]["clientId"], "cid-fake")
        self.assertEqual(blob["google"]["refreshToken"], "", "disconnect cleared the refresh token in the keyring blob")


if __name__ == "__main__":
    unittest.main()
