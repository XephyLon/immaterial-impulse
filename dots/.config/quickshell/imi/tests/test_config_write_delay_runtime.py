#!/usr/bin/env python3
"""How long the settings window's faster config flush lasts.

`ConfigWriteDelayRuntimeTest.qml` builds the real `Settings` scope - the same
one the panel family loads - under this harness's own headless weston and
session bus, and reads `Config.readWriteDelay` back across an open, a close, a
second open, a second claimant, and a claim whose declaring object is destroyed
under it.

The defect it exists to refuse: `modules/imi/settings/SettingsContent.qml` set
`Config.readWriteDelay = 0` from its own `Component.onCompleted` and never
restored it. `Config` is a singleton, and the settings host is built at
`Config.ready` rather than when its window opens (the warm-up's gate - see
2581cafae ("fix(settings): the warm-up is gated on Config.ready, not on the
window")), so the shell's config writes had been undebounced from startup for
the whole session on every machine, whether or not anyone opened Settings.

What the debounce is for is in `Config.qml`'s own comment: `writeAdapter()`
serializes the whole schema and `configFileView` watches the file it just
wrote, so an undebounced write is a full serialize, an inotify event, a full
re-read and a full deserialize per property - and with the reload landing
immediately, a second property written in between is deserialized away by a
file that does not carry it yet.

The first check is the leak verbatim: the host is built and the delay is still
the default. The rest are the lifetime questions "save the previous value and
put it back" gets wrong - repeated opens, two claimants, and a claim whose
owner is destroyed, which is what a hot reload does to a surface holding one
and is the case where nobody is left to run a restore.

Brings its own headless weston (tests/nested_display.py) and its own session
bus (`dbus-run-session`). Skips when weston, qs or dbus-run-session are
missing, as in CI.
"""

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "ConfigWriteDelayRuntimeTest.qml"

# A literal, never read back out of the harness's own output: a step list that
# loses an entry must redden here instead of reporting `failures: 0` for a
# shorter run.
EXPECTED_CHECKS = 10


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class ConfigWriteDelayRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-config-write-delay-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        shell_config = self.home / "config" / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        # An empty config on purpose: the delay under test is the QML default,
        # and nothing here may depend on the maintainer's own settings.
        (shell_config / "config.json").write_text(json.dumps({}, indent=2))

    def test_the_faster_flush_lasts_exactly_as_long_as_the_window(self):
        env = nested_display.start(self, "config-write-delay", width=1200, height=800)
        env["XDG_CONFIG_HOME"] = str(self.home / "config")
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")

        # dbus-run-session, not the inherited bus: nothing this harness reads
        # may depend on what the developer happens to be running.
        proc = subprocess.run(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=300)
        output = proc.stdout + proc.stderr

        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[ConfigWriteDelay] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")


if __name__ == "__main__":
    unittest.main()
