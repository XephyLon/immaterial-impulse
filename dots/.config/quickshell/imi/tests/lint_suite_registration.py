#!/usr/bin/env python3
"""Every register in tests/ must be named by run_tests.sh.

A test file that exists but is not wired into the suite passes every hand
run and protects nothing: test_bar_popup_section_entrance.py sat unwired
with its "mutations all caught" receipt earned only ever by hand. This is
the one failure mode the suite cannot see about itself, so it is checked
from outside the registers.
"""

import pathlib
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
RUNNER = (TESTS_DIR / "run_tests.sh").read_text()

missing = [
    p.name
    for pattern in ("test_*.py", "lint_*.py")
    for p in sorted(TESTS_DIR.glob(pattern))
    if p.name not in RUNNER
]

if missing:
    for name in missing:
        print(f"UNREGISTERED: tests/{name} is not named in run_tests.sh")
    sys.exit(1)

print(f"Suite registration lint passed (every test_*.py and lint_*.py is wired in)")
