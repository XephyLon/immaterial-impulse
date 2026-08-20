#!/usr/bin/env python3
"""The physical-key reader: what it emits, and what it must never emit.

`scripts/keyboard/key_monitor.py` is the one thing in this shell that reads
every key on the machine, so its contract is as much about what it refuses to
do as about what it reports. Two of the checks here are privacy properties
rather than behaviour: it emits KEYCODES and never characters, and it holds no
state that outlives a keypress. Both are cheap to break in a later "improvement"
(a keymap lookup to make the output readable, a buffer to coalesce events) and
neither would fail anything else in the suite.

The reader is driven from recorded `input_event` bytes rather than from a
keyboard: the struct is stable kernel ABI, so a file of them exercises the
parse, the repeat suppression and the device dedup with no hardware, no fake
/dev and no privilege.
"""

import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts/keyboard/key_monitor.py"
SERVICE = ROOT / "services/KeyMonitor.qml"
OSK_KEY = ROOT / "modules/imi/onScreenKeyboard/OskKey.qml"

EVENT_FORMAT = "llHHi"
EV_KEY = 0x01
EV_SYN = 0x00
EV_MSC = 0x04


def events(*triples):
    return b"".join(struct.pack(EVENT_FORMAT, 0, 0, kind, code, value)
                    for kind, code, value in triples)


def run(payload, extra_devices=0):
    paths = []
    try:
        with tempfile.NamedTemporaryFile(suffix=".dev", delete=False) as handle:
            handle.write(payload)
            paths.append(handle.name)
        for _ in range(extra_devices):
            link = paths[0] + f".link{len(paths)}"
            os.symlink(paths[0], link)
            paths.append(link)
        argv = [sys.executable, str(SCRIPT), "--once"]
        for path in paths:
            argv += ["--device", path]
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=20)
        lines = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
        return proc, lines
    finally:
        for path in paths:
            try:
                os.unlink(path)
            except OSError:
                pass


class WhatItReports(unittest.TestCase):
    def test_a_press_and_a_release_are_one_line_each(self):
        proc, lines = run(events((EV_KEY, 30, 1), (EV_KEY, 30, 0)))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(lines[0]["state"], "watching")
        self.assertEqual(lines[1:], [{"code": 30, "down": 1}, {"code": 30, "down": 0}])

    def test_an_auto_repeat_reports_nothing(self):
        """Value 2 is the kernel repeating a key that is already held. The OSK
        would redraw a key it is already drawing, once per repeat, for as long
        as a key is held down."""
        _, lines = run(events((EV_KEY, 30, 1), (EV_KEY, 30, 2), (EV_KEY, 30, 2),
                              (EV_KEY, 30, 0)))
        self.assertEqual(lines[1:], [{"code": 30, "down": 1}, {"code": 30, "down": 0}])

    def test_everything_that_is_not_a_key_is_ignored(self):
        """A keyboard emits SYN and MSC around every press. Forwarding those
        would light whatever key happens to share the code."""
        _, lines = run(events((EV_SYN, 0, 0), (EV_MSC, 4, 458792), (EV_KEY, 42, 1)))
        self.assertEqual(lines[1:], [{"code": 42, "down": 1}])

    def test_two_names_for_one_device_are_read_once(self):
        """A single keyboard appears under several by-path names on this
        machine. Two descriptors on one device report every press twice, and a
        release from the second would clear a key the first still holds."""
        proc, lines = run(events((EV_KEY, 30, 1)), extra_devices=2)
        self.assertEqual(lines[0], {"state": "watching", "devices": 1})
        self.assertEqual(lines[1:], [{"code": 30, "down": 1}])

    def test_no_readable_device_is_not_an_error(self):
        """Reading /dev/input needs the `input` group. A machine without it is
        the common case: the shell asks, gets `unavailable`, and draws no
        highlighting - rather than a red line in the log on every start."""
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), "--once", "--device", "/nonexistent/device"],
            capture_output=True, text=True, timeout=20)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout.splitlines()[0])["state"], "unavailable")


class WhatItMustNeverReport(unittest.TestCase):
    def test_the_output_carries_codes_and_nothing_else(self):
        """The privacy property, pinned as a shape rather than as a promise: a
        line has exactly `code` and `down`. A keymap lookup added later to make
        the output readable would turn this from a position report into a
        transcript of what the user typed."""
        _, lines = run(events((EV_KEY, 30, 1), (EV_KEY, 42, 1), (EV_KEY, 30, 0)))
        for line in lines[1:]:
            self.assertEqual(set(line), {"code", "down"}, line)
            self.assertIsInstance(line["code"], int)

    def test_the_reader_never_writes_a_file(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for forbidden in ("open(", "Path(", "logging", "shelve", "pickle"):
            self.assertNotIn(
                forbidden, source.replace("os.open(", "").replace("sys.stdout", ""),
                f"the key reader references {forbidden!r} - it must keep no "
                f"record of what it read")


class WhenItIsAllowedToRun(unittest.TestCase):
    """The lifetime IS the safeguard, so it is pinned rather than described."""

    def test_the_watch_is_the_osk_being_open_and_nothing_else(self):
        text = SERVICE.read_text(encoding="utf-8")
        self.assertIn("readonly property bool watching: GlobalStates.oskOpen", text,
                      "the reader's lifetime must be the OSK's own open state, "
                      "and readonly so nothing else can extend it")
        self.assertIn("showPhysicalKeys", text,
                      "the user must be able to turn it off entirely")

    def test_the_process_has_no_running_binding(self):
        """A `running:` binding on anything that can go true without the OSK
        being open is a reader nobody remembers starting - and CONTRIBUTING
        forbids a persistent one for streaming processes anyway."""
        text = SERVICE.read_text(encoding="utf-8")
        self.assertIn("running: false", text)
        self.assertNotIn("running: root.watching", text)

    def test_the_held_set_is_cleared_when_the_osk_closes(self):
        """A key still down when the OSK closes would be drawn as down the next
        time it opens: its release went to a process that no longer exists."""
        text = SERVICE.read_text(encoding="utf-8")
        after = text.split("onWatchingChanged", 1)[1]
        self.assertIn("root.pressed = ({})", after)

    def test_the_key_draws_the_physical_state_separately_from_its_own(self):
        """A key can be both: the user taps the OSK's Shift while holding the
        real one. Folding the two into one flag makes the tap clear the
        hardware's state or the reverse."""
        text = OSK_KEY.read_text(encoding="utf-8")
        self.assertIn("physicallyDown: KeyMonitor.isDown(root.keycode)", text)
        self.assertIn("root.physicallyDown ?", text)


if __name__ == "__main__":
    unittest.main()
