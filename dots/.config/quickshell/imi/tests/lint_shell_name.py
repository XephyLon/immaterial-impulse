#!/usr/bin/env python3
"""Fail if a script still names the shell by a path that does not exist.

The shell was renamed `ii` -> `imi` (v0.7.0). Five scripts kept
`QUICKSHELL_CONFIG_NAME="ii"`, and the one that mattered - `applycolor.sh` -
opens with `cd "$CONFIG_DIR" || exit`. Pointed at `~/.config/quickshell/ii`,
which no longer exists, that `cd` fails and the script exits before doing
anything: terminal palettes stopped regenerating and no OSC sequence was ever
broadcast again. Nothing failed loudly, because exiting 0-ish on a missing
directory looks exactly like "nothing to do".

The other four only assigned the variable without dereferencing it, which is
the worse shape long-term: the bug is dormant until someone uses it.

So this pins the assignment itself rather than any one consumer.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = "imi"
ASSIGNMENT = re.compile(r'^\s*QUICKSHELL_CONFIG_NAME=["\']?([\w-]+)', re.M)


class ShellNameLint(unittest.TestCase):
    def test_every_script_names_the_current_shell(self):
        offenders = []
        for path in sorted(ROOT.rglob("*.sh")):
            for match in ASSIGNMENT.finditer(path.read_text(errors="ignore")):
                if match.group(1) != EXPECTED:
                    offenders.append(
                        f"{path.relative_to(ROOT)}: "
                        f'QUICKSHELL_CONFIG_NAME="{match.group(1)}"')
        self.assertEqual(offenders, [], "\n".join(
            ["scripts naming a shell directory that does not exist:"] + offenders))

    def test_the_assignment_still_exists_somewhere(self):
        """Guards the lint itself: a rename that also drops the variable would
        otherwise make this pass by finding nothing."""
        found = [p for p in ROOT.rglob("*.sh")
                 if ASSIGNMENT.search(p.read_text(errors="ignore"))]
        self.assertTrue(found, "no script assigns QUICKSHELL_CONFIG_NAME at all")


if __name__ == "__main__":
    unittest.main()
