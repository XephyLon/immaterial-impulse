#!/usr/bin/env python3
"""The shell collects its JavaScript heap on a fixed cadence.

QV4's incremental collector ran, and the shell still grew 2-3 MiB/min idle
(2.6 GB after ten hours); a forced gc() reclaimed all of it and a shell
calling it every 30 s stayed flat. shell.qml therefore runs gc() from a
repeating Timer. This pins that the timer exists, repeats, and fires between
once a minute and once a quarter hour - often enough to bound the growth to
tens of MB, rarely enough that its pause stays invisible.
"""
import re
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1] / "shell.qml"


class HeapJanitor(unittest.TestCase):
    def setUp(self):
        self.src = SHELL.read_text(encoding="utf-8")

    def _timer(self):
        # Top-level children of ShellRoot close at four-space indent, so a
        # handler block inside the timer does not end the match early.
        for m in re.finditer(r"^    Timer\s*\{(.*?)^    \}", self.src, re.S | re.M):
            body = m.group(1)
            if re.search(r"onTriggered:\s*(\{[^}]*)?\bgc\(\)", body):
                return body
        self.fail("shell.qml has no Timer whose onTriggered calls gc()")

    def test_gc_timer_exists_and_repeats(self):
        body = self._timer()
        self.assertRegex(body, r"running:\s*true")
        self.assertRegex(body, r"repeat:\s*true")

    def test_cadence_is_between_one_and_fifteen_minutes(self):
        body = self._timer()
        m = re.search(r"interval:\s*([0-9*\s]+)", body)
        self.assertIsNotNone(m, "interval must be a literal expression")
        ms = eval(m.group(1).strip(), {"__builtins__": {}}, {})  # digits and * only
        self.assertGreaterEqual(ms, 60_000)
        self.assertLessEqual(ms, 15 * 60_000)


if __name__ == "__main__":
    unittest.main()
