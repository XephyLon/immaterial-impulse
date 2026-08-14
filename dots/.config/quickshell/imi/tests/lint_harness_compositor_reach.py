#!/usr/bin/env python3
"""No harness may reach the developer's own compositor.

`hyprctl` chooses which Hyprland to talk to from HYPRLAND_INSTANCE_SIGNATURE
alone. It does not consult WAYLAND_DISPLAY, so a script that starts a nested
compositor, points WAYLAND_DISPLAY at it, and then calls plain `hyprctl` is
still talking to the CALLER's session. `run_notification_blur_probe.sh` ended
with `hyprctl dispatch exit` for exactly that reason: every isolation the
script built - its own bus, its own XDG dirs, its own compositor - and the
teardown reached out and closed the developer's desktop.

The rule: a harness that invokes hyprctl must either fake the binary, or set
the signature for the instance it means. Passing `-j` to read from a session
the test did not create is also out - a test whose answer depends on the
machine it runs on is not a test.

Exits non-zero listing offenders. Wired into run_tests.sh.
"""

import re
import sys
from pathlib import Path

HARNESS_DIR = Path(__file__).resolve().parent
# Deliberately narrow: an INVOCATION, not a mention. A shell line whose first
# word is hyprctl, or a python line handing it to subprocess. Everything else
# in these files - docstrings explaining what the shell does with hyprctl,
# assertions about the shell's own source, fake binaries written to a temp
# PATH - names it without ever reaching a compositor, and a lint that flags
# those is one nobody can leave switched on.
SHELL_INVOCATION = re.compile(r"^\s*(?!#)(?:[^#]*[;&|]\s*)?hyprctl\s")
PYTHON_INVOCATION = re.compile(r"(subprocess|Popen|check_output|\brun\()[^\n]*[\"']hyprctl[\"']")


def offenders():
    found = []
    for path in sorted(list(HARNESS_DIR.glob("*.sh")) + list(HARNESS_DIR.glob("*.py"))):
        if path.name == Path(__file__).name:
            continue
        source = path.read_text(encoding="utf-8")
        # A harness that sets the signature has said which instance it means.
        if "HYPRLAND_INSTANCE_SIGNATURE" in source:
            continue
        matcher = SHELL_INVOCATION if path.suffix == ".sh" else PYTHON_INVOCATION
        for number, line in enumerate(source.splitlines(), 1):
            if matcher.search(line):
                found.append((path.name, number, line.strip()))
    return found


def main():
    found = offenders()
    if found:
        print("Harness compositor-reach lint FAILED: hyprctl resolves its "
              "instance from HYPRLAND_INSTANCE_SIGNATURE, not WAYLAND_DISPLAY, "
              "so these reach the caller's own session:", file=sys.stderr)
        for name, number, line in found:
            print(f"  {name}:{number}: {line}", file=sys.stderr)
        return 1
    scanned = len(list(HARNESS_DIR.glob("*.sh"))) + len(list(HARNESS_DIR.glob("*.py")))
    print(f"Harness compositor-reach lint passed ({scanned} harness files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
