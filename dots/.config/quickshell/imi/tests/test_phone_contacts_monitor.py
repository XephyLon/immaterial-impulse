#!/usr/bin/env python3
"""scripts/phone/contacts_monitor.py: what it reads, what it emits, and when.

The reader is driven against a throwaway `kpeoplevcard/kdeconnect-<id>/`
tree, never the machine's own: the vCards KDE Connect writes there are the
user's contacts, and a fixture is the only thing that may be committed. The
fixture is shaped after the real files - vCard 2.1 with QUOTED-PRINTABLE
names carrying a soft line break (a trailing `=` continued on a line with NO
leading space, which a plain unfold truncates), a base64 photo folded over
several lines, several TELs with PREF on one of them, a card that is nothing
but a number, and a card with nothing in it at all.

Three things are pinned beyond the parse. A snapshot is published only when
the set changes (the SHA-256 rule), so a watcher that re-reads on every
directory tick costs the shell nothing while nothing moved. A missing source
is an `error` event and a clean exit, never a traceback. And the watch mode
keeps running whichever way it can: through `gio monitor -d` when gio is on
PATH (driven here by a fake that reports a change when the directory listing
moves), and through a 3 s poll when it is not.
"""

import base64
import importlib.util
import io
import json
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "phone" / "contacts_monitor.py"

SPEC = importlib.util.spec_from_file_location("contacts_monitor", SCRIPT)
contacts_monitor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(contacts_monitor)

JPEG_BYTES = b"\xff\xd8\xff\xe0" + bytes(range(64)) * 3
PNG_BYTES = b"\x89PNG\r\n\x1a\n" + bytes(range(32))


def _fold_base64(data: bytes, width: int = 60) -> str:
    text = base64.b64encode(data).decode("ascii")
    chunks = [text[i:i + width] for i in range(0, len(text), width)]
    return "\n ".join(chunks)


# "أحمد علي" as Android's vCard 2.1 exporter spells it: QUOTED-PRINTABLE,
# soft-wrapped with a trailing `=` and the continuation on an unindented line.
ALICE = (
    "BEGIN:VCARD\n"
    "VERSION:2.1\n"
    "N;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=D8=B9=D9=84=D9=8A;=D8=A3=D8=AD=D9=85=D8=AF;;;\n"
    "FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=D8=A3=D8=AD=D9=85=D8=AF =D8=B9=D9=84=\n"
    "=D9=8A\n"
    "TEL;CELL;PREF:+1 (555) 010-0001\n"
    "TEL;HOME:555 010 0002\n"
    "TEL;CELL:+1 (555) 010-0001\n"
    "EMAIL;PREF;HOME:ahmed@example.com\n"
    "ORG:Example Corp\n"
    "PHOTO;ENCODING=BASE64;JPEG:" + _fold_base64(JPEG_BYTES) + "\n"
    "\n"
    "X-KDECONNECT-ID-DEV-dev1:42\n"
    "REV:20260101T000000Z\n"
    "END:VCARD\n"
)

BOB = (
    "BEGIN:VCARD\n"
    "VERSION:3.0\n"
    "UID:bob-uid-1\n"
    "FN:Bob Stone\n"
    "N:Stone;Bob;;;\n"
    "TEL;TYPE=CELL,VOICE:+15550100010\n"
    "TEL;TYPE=WORK,PREF:+15550100011\n"
    "TEL;X-CUSTOM(CHARSET=UTF-8,ENCODING=QUOTED-PRINTABLE,=D9=85):+15550100012\n"
    "EMAIL;TYPE=WORK:bob@example.com\n"
    "PHOTO;ENCODING=b;TYPE=PNG:" + base64.b64encode(PNG_BYTES).decode("ascii") + "\n"
    "END:VCARD\n"
)

CARLA = (
    "BEGIN:VCARD\n"
    "VERSION:4.0\n"
    "FN:Carla Díaz\n"
    "N:Díaz;Carla;;;\n"
    "TEL;VALUE=uri;TYPE=home:tel:+15550100020\n"
    "PHOTO:data:image/png;base64,iVBORw0KGgo=\n"
    "END:VCARD\n"
)

NAMELESS = (
    "BEGIN:VCARD\n"
    "VERSION:2.1\n"
    "N:;+15550100099;;;\n"
    "FN:+15550100099\n"
    "TEL;CELL:+15550100099\n"
    "END:VCARD\n"
)

EMPTY = "BEGIN:VCARD\nVERSION:2.1\nNOTE:nothing here\nEND:VCARD\n"

OTHER_DEVICE = (
    "BEGIN:VCARD\nVERSION:2.1\nFN:Dana Other\nN:Other;Dana;;;\n"
    "TEL;CELL:+15550100030\nEND:VCARD\n"
)


class Fixture:
    """A temp XDG_DATA_HOME holding kpeoplevcard/kdeconnect-dev1 (four real
    contacts plus an empty card) and an older kdeconnect-dev2 (one contact)."""

    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.data_home = Path(self.tmp.name) / "data"
        self.root = self.data_home / "kpeoplevcard"
        self.dev1 = self.root / "kdeconnect-dev1"
        self.dev2 = self.root / "kdeconnect-dev2"
        self.dev1.mkdir(parents=True)
        self.dev2.mkdir(parents=True)
        for name, text in (("alice", ALICE), ("bob", BOB), ("carla", CARLA),
                           ("nameless", NAMELESS), ("empty", EMPTY)):
            (self.dev1 / f"{name}.vcf").write_text(text, encoding="utf-8")
        (self.dev2 / "dana.vcf").write_text(OTHER_DEVICE, encoding="utf-8")
        old = time.time() - 3600
        os.utime(self.dev2, (old, old))
        now = time.time()
        os.utime(self.dev1, (now, now))

    def env(self, path=None):
        env = {k: v for k, v in os.environ.items() if not k.startswith("XDG_")}
        env["XDG_DATA_HOME"] = str(self.data_home)
        env["HOME"] = self.tmp.name
        if path is not None:
            env["PATH"] = path
        return env

    def cleanup(self):
        self.tmp.cleanup()


def run_once(fixture, *args, env=None):
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "--once", *args],
        capture_output=True, text=True, timeout=30, env=env or fixture.env())
    events = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
    return proc, events


class Stream:
    """Lines of a running monitor, as parsed events, with a timeout per wait."""

    def __init__(self, proc):
        self.proc = proc
        self.events = queue.Queue()
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        for raw in self.proc.stdout:
            line = raw.decode("utf-8", errors="replace").strip()
            if line:
                self.events.put(json.loads(line))
        self.events.put(None)

    def expect(self, event, timeout):
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f"no {event!r} event within {timeout}s")
            try:
                message = self.events.get(timeout=remaining)
            except queue.Empty:
                raise AssertionError(f"no {event!r} event within {timeout}s")
            if message is None:
                raise AssertionError(f"monitor exited before a {event!r} event")
            if message.get("event") == event:
                return message

    def expect_none(self, seconds):
        try:
            message = self.events.get(timeout=seconds)
        except queue.Empty:
            return
        raise AssertionError(f"expected silence, got {message}")


def start_watch(fixture, env, *args):
    proc = subprocess.Popen(
        [sys.executable, str(SCRIPT), *args],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    return proc, Stream(proc)


def stop(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
    proc.stdout.close()
    proc.stderr.close()


FAKE_GIO = """#!/bin/sh
# A stand-in for `gio monitor -d <dir>`: prints one line whenever the
# directory listing changes, the way the real one prints one per event.
dir="$3"
prev=""
while :; do
    cur=$(ls -l "$dir" 2>/dev/null)
    if [ "$cur" != "$prev" ]; then
        [ -n "$prev" ] && echo "$dir: $dir/changed.vcf: changed"
        prev="$cur"
    fi
    sleep 0.1
done
"""


class ContactsMonitorOnceTest(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture()
        self.addCleanup(self.fixture.cleanup)

    def test_once_reports_the_device_directory_then_the_snapshot_and_exits_zero(self):
        proc, events = run_once(self.fixture, "--device", "dev1")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stderr, "")
        self.assertEqual([e["event"] for e in events], ["ready", "snapshot"])
        ready = events[0]
        self.assertEqual(ready["sourcePath"], str(self.fixture.dev1))
        self.assertEqual(ready["count"], 4, "the empty card must be dropped, the nameless one kept")
        self.assertEqual(len(events[1]["contacts"]), 4)

    def test_the_snapshot_shape(self):
        _, events = run_once(self.fixture, "--device", "dev1")
        contacts = {c["displayName"]: c for c in events[1]["contacts"]}
        self.assertEqual(set(contacts), {"أحمد علي", "Bob Stone", "Carla Díaz", "+15550100099"})
        for contact in contacts.values():
            self.assertEqual(set(contact), {"id", "displayName", "givenName", "familyName",
                                            "organization", "phones", "emails", "photo",
                                            "nameless", "source"})
            self.assertEqual(contact["source"], "kdeconnect-dev1")

        alice = contacts["أحمد علي"]
        self.assertEqual(alice["givenName"], "أحمد")
        self.assertEqual(alice["familyName"], "علي")
        self.assertEqual(alice["organization"], "Example Corp")
        self.assertEqual(alice["id"], "42", "the KDE Connect device id line is the uid when there is no UID")
        self.assertEqual(alice["phones"], [
            {"value": "+1 (555) 010-0001", "normalized": "+15550100001", "type": "mobile", "primary": True},
            {"value": "555 010 0002", "normalized": "5550100002", "type": "home", "primary": False},
        ], "the duplicate mobile number is folded, PREF marks the primary")
        self.assertEqual(alice["emails"], [{"value": "ahmed@example.com", "type": "home", "primary": True}])
        self.assertTrue(alice["photo"].startswith("data:image/jpeg;base64,"))
        self.assertEqual(base64.b64decode(alice["photo"].split(",", 1)[1]), JPEG_BYTES,
                         "a folded 2.1 photo must survive unfolding byte for byte")
        self.assertFalse(alice["nameless"])

        bob = contacts["Bob Stone"]
        self.assertEqual(bob["id"], "bob-uid-1")
        self.assertEqual([(p["type"], p["primary"]) for p in bob["phones"]],
                         [("mobile", False), ("work", True), ("mobile", False)],
                         "a 3.0 TYPE list resolves, PREF wins over 'first is primary', an X- type is a mobile")
        self.assertEqual(bob["emails"], [{"value": "bob@example.com", "type": "work", "primary": True}])
        self.assertEqual(bob["photo"], "data:image/png;base64," + base64.b64encode(PNG_BYTES).decode("ascii"))

        carla = contacts["Carla Díaz"]
        self.assertEqual(carla["phones"], [
            {"value": "+15550100020", "normalized": "+15550100020", "type": "home", "primary": True}
        ], "a 4.0 tel: URI is a number")
        self.assertEqual(carla["photo"], "data:image/png;base64,iVBORw0KGgo=",
                         "a 4.0 inline photo is already a data URI and passes through")
        self.assertEqual(len(carla["id"]), 16, "a card with no UID gets a stable derived id")

        nameless = contacts["+15550100099"]
        self.assertTrue(nameless["nameless"])
        self.assertEqual(nameless["phones"][0]["type"], "mobile")

    def test_contacts_are_sorted_by_display_name(self):
        _, events = run_once(self.fixture, "--device", "dev1")
        names = [c["displayName"] for c in events[1]["contacts"]]
        self.assertEqual(names, sorted(names, key=str.lower))

    def test_an_unknown_device_falls_back_to_the_newest_directory(self):
        _, events = run_once(self.fixture, "--device", "nobody")
        self.assertEqual(events[0]["sourcePath"], str(self.fixture.dev1))
        _, events = run_once(self.fixture, "--device", "dev2")
        self.assertEqual(events[0]["sourcePath"], str(self.fixture.dev2))
        self.assertEqual(events[0]["count"], 1)
        _, events = run_once(self.fixture)
        self.assertEqual(events[0]["sourcePath"], str(self.fixture.dev1), "no --device means the newest")

    def test_no_source_is_an_error_event_and_a_clean_exit(self):
        shutil.rmtree(self.fixture.root)
        proc, events = run_once(self.fixture, "--device", "dev1")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["event"], "error")
        self.assertEqual(events[0]["code"], "no_contact_source")
        self.assertTrue(events[0]["message"])

    def test_an_unchanged_set_publishes_no_second_snapshot(self):
        os.environ["XDG_DATA_HOME"] = str(self.fixture.data_home)
        self.addCleanup(os.environ.pop, "XDG_DATA_HOME", None)
        monitor = contacts_monitor.ContactMonitor("dev1")

        def emitted():
            out = io.StringIO()
            with redirect_stdout(out):
                self.assertTrue(monitor.update_and_emit())
            return [json.loads(line) for line in out.getvalue().splitlines() if line.strip()]

        self.assertEqual([e["event"] for e in emitted()], ["ready", "snapshot"])
        self.assertEqual(emitted(), [], "the SHA-256 of an unchanged set publishes nothing")
        (self.fixture.dev1 / "erin.vcf").write_text(
            "BEGIN:VCARD\nVERSION:2.1\nFN:Erin New\nTEL;CELL:+15550100040\nEND:VCARD\n")
        again = emitted()
        self.assertEqual([e["event"] for e in again], ["ready", "snapshot"])
        self.assertEqual(again[0]["count"], 5)


class ContactsMonitorWatchTest(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture()
        self.addCleanup(self.fixture.cleanup)
        self.bin = Path(self.fixture.tmp.name) / "bin"
        self.bin.mkdir()
        self.empty_bin = Path(self.fixture.tmp.name) / "nothing"
        self.empty_bin.mkdir()

    def with_fake_gio(self):
        gio = self.bin / "gio"
        gio.write_text(FAKE_GIO)
        gio.chmod(0o755)
        return self.fixture.env(path=f"{self.bin}:{os.environ.get('PATH', '')}")

    def without_gio(self):
        return self.fixture.env(path=str(self.empty_bin))

    def test_a_change_gio_reports_republishes_after_the_debounce(self):
        proc, stream = start_watch(self.fixture, self.with_fake_gio(), "--device", "dev1")
        self.addCleanup(stop, proc)
        self.assertEqual(stream.expect("ready", 10)["count"], 4)
        stream.expect("snapshot", 5)
        stream.expect_none(1.0)
        (self.fixture.dev1 / "erin.vcf").write_text(
            "BEGIN:VCARD\nVERSION:2.1\nFN:Erin New\nTEL;CELL:+15550100040\nEND:VCARD\n")
        self.assertEqual(stream.expect("ready", 5)["count"], 5)
        snapshot = stream.expect("snapshot", 5)
        self.assertIn("Erin New", [c["displayName"] for c in snapshot["contacts"]])
        self.assertIsNone(proc.poll(), "the watcher stays up after a change")

    def test_without_gio_the_watcher_polls(self):
        proc, stream = start_watch(self.fixture, self.without_gio(), "--device", "dev1")
        self.addCleanup(stop, proc)
        self.assertEqual(stream.expect("ready", 10)["count"], 4)
        stream.expect("snapshot", 5)
        (self.fixture.dev1 / "erin.vcf").write_text(
            "BEGIN:VCARD\nVERSION:2.1\nFN:Erin New\nTEL;CELL:+15550100040\nEND:VCARD\n")
        self.assertEqual(stream.expect("ready", contacts_monitor.POLL_SECONDS + 5)["count"], 5)
        stream.expect("snapshot", 5)

    def test_a_missing_source_is_reported_once_and_found_when_it_appears(self):
        shutil.rmtree(self.fixture.root)
        proc, stream = start_watch(self.fixture, self.without_gio(), "--device", "dev1")
        self.addCleanup(stop, proc)
        self.assertEqual(stream.expect("error", 10)["code"], "no_contact_source")
        stream.expect_none(contacts_monitor.POLL_SECONDS + 1)
        self.assertIsNone(proc.poll(), "no source is a state to wait in, not an exit")
        self.fixture.dev1.mkdir(parents=True)
        (self.fixture.dev1 / "bob.vcf").write_text(BOB, encoding="utf-8")
        self.assertEqual(stream.expect("ready", contacts_monitor.POLL_SECONDS + 5)["count"], 1)
        stream.expect("snapshot", 5)


if __name__ == "__main__":
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
