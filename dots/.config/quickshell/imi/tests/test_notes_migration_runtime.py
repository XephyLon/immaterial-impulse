#!/usr/bin/env python3
"""Behavioural cover for the note store migration, against real files.

`tst_notes_store.qml` pins the parsing rules; this drives the whole service -
two asynchronous FileView loads, the asynchronous Config load they are gated
on, the write, and the one-shot marker - by launching
`NotesMigrationRuntimeTest.qml` in a real Quickshell process against a
throwaway XDG_STATE_HOME/XDG_CONFIG_HOME, once per on-disk state a user can
actually be in.

The two properties worth the process launch:
  * content in either old store (or both) still exists afterwards;
  * neither source file is modified or removed by reading it.

Needs a Wayland session and `qs` on PATH, so it skips in CI the same way the
design-system compile check does.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nested_display  # noqa: E402
HARNESS = ROOT / "NotesMigrationRuntimeTest.qml"

LEGACY_NOTES = json.dumps([
    {"id": "d1", "content": "desktop one", "attachments": [], "createdAt": 5},
    {"id": "d2", "content": "desktop two", "attachments": [], "createdAt": 6},
])


# The harness prints how many checks it ran. This number is a literal rather
# than anything read back from that output: a harness whose step list shrinks
# must redden here instead of reporting `failures: 0` for a shorter run.
EXPECTED_CHECKS = 7


def _runtime_available():
    return nested_display.available()


def _digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


@unittest.skipUnless(_runtime_available(),
                     "needs qs, weston and dbus-run-session on PATH")
class NotesMigrationRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-notes-runtime-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.user = self.home / "state" / "quickshell" / "user"
        self.user.mkdir(parents=True)

    @property
    def notes_file(self):
        return self.user / "notes.txt"

    @property
    def legacy_file(self):
        return self.user / "desktopnotes.txt"

    @property
    def config_file(self):
        return self.home / "config" / "immaterial-impulse" / "config.json"

    def seed(self, notes=None, legacy=None):
        if notes is not None:
            self.notes_file.write_text(notes)
        if legacy is not None:
            self.legacy_file.write_text(legacy)

    def launch(self, expected):
        env = nested_display.start(self, "notes")
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CONFIG_HOME"] = str(self.home / "config")
        env["NOTES_EXPECT"] = json.dumps(expected)
        # dbus-run-session, not the inherited DBUS_SESSION_BUS_ADDRESS: a
        # shell reading MPRIS, UPower or a portal off the developer's bus
        # measures their session rather than this tree. Through the retry
        # wrapper: the nested bus has collapsed under a green harness before
        # (all checks ok, summary line lost), and that is the environment's
        # failure, retried once, not the code's.
        proc = nested_display.run_harness_with_bus_retry(
            ["dbus-run-session", "--", "qs", "-p", str(HARNESS)],
            env=env, cwd=str(ROOT), timeout=180,
            marker=f"[NotesMigration] checks: {EXPECTED_CHECKS} failures: 0")
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn(f"[NotesMigration] checks: {EXPECTED_CHECKS} failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")
        return output

    def stored_notes(self):
        parsed = json.loads(self.notes_file.read_text())
        self.assertIsInstance(parsed, list)
        return [note["content"] for note in parsed]

    def assertMarkerSet(self):
        config = json.loads(self.config_file.read_text())
        self.assertTrue(config.get("notes", {}).get("importedLegacyStore"),
                        "the legacy import marker was not written")

    def test_plaintext_scratchpad_survives_as_a_note(self):
        self.seed(notes="buy milk\n- and eggs")
        self.launch(["buy milk\n- and eggs"])
        self.assertEqual(self.stored_notes(), ["buy milk\n- and eggs"])
        self.assertMarkerSet()

    def test_legacy_desktop_notes_are_imported(self):
        self.seed(legacy=LEGACY_NOTES)
        before = _digest(self.legacy_file)
        self.launch(["desktop one", "desktop two"])
        self.assertEqual(self.stored_notes(), ["desktop one", "desktop two"])
        self.assertEqual(_digest(self.legacy_file), before,
                         "the legacy store must be read, never rewritten")

    def test_content_in_both_stores_survives(self):
        self.seed(notes="scratchpad text", legacy=LEGACY_NOTES)
        legacy_before = _digest(self.legacy_file)
        self.launch(["scratchpad text", "desktop one", "desktop two"])
        self.assertEqual(self.stored_notes(),
                         ["scratchpad text", "desktop one", "desktop two"])
        self.assertEqual(_digest(self.legacy_file), legacy_before)
        self.assertTrue(self.legacy_file.exists())

    def test_no_stores_at_all_is_not_an_error(self):
        self.launch([])
        self.assertEqual(self.stored_notes(), [])

    def test_corrupt_stores_are_kept_rather_than_reset(self):
        self.seed(notes='{"half written', legacy='[{"id": "d1", "content": "trunc')
        self.launch(['{"half written', '[{"id": "d1", "content": "trunc'])

    # The reason the marker exists: desktopnotes.txt stays on disk forever, so
    # a second launch must not resurrect a note the user deleted in between.
    def test_a_deleted_legacy_note_does_not_come_back(self):
        self.seed(legacy=LEGACY_NOTES)
        self.launch(["desktop one", "desktop two"])
        self.assertMarkerSet()

        kept = [note for note in json.loads(self.notes_file.read_text())
                if note["content"] != "desktop one"]
        self.notes_file.write_text(json.dumps(kept))

        self.launch(["desktop two"])
        self.assertEqual(self.stored_notes(), ["desktop two"])


if __name__ == "__main__":
    unittest.main()
