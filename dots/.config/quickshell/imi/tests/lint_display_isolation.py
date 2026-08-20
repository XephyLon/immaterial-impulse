#!/usr/bin/env python3
#
# Regression guard: a harness that launches `qs` brings its own compositor.
#
# `qs -p` on the session's WAYLAND_DISPLAY maps its surfaces on the session's
# compositor, so a suite run opened and closed real windows across whatever the
# user was doing - reported as "tests spawn a lot of windows quickly". Every
# `run_*_probe.sh` already nested its own headless weston; five Python
# harnesses never did, and they are the ones that flashed.
#
# It is not only a nuisance. A harness mapping a LAYER surface on the live
# display covers the user's screen, and the lock harness had to be nested
# because a real WlSessionLock on this machine suspends the laptop. The
# difference between "annoying" and "destructive" here is which surface the
# harness happens to build.
#
# `tests/nested_display.py` is the one way to do it: three environment
# variables and a process, each silent when wrong. Notably HYPRLAND_INSTANCE_
# SIGNATURE, which `hyprctl` reads and nothing else - a harness that redirects
# every other variable and leaves that one still talks to the user's
# compositor (AGENT.md records it; run_notification_blur_probe.sh shipped it).
#
# So: a Python harness that launches `qs` must bring a compositor - either
# through that module or by starting weston itself, which several harnesses did
# before the module existed and which is equally correct. The check asks for
# the PROPERTY (a compositor of its own), not for the helper: a first version
# demanded the import and flagged twenty-four harnesses that were already
# nesting perfectly well.
#
# Exits non-zero. Wired into run_tests.sh / CI.

import ast
import re
import sys
from pathlib import Path

TESTS = Path(__file__).resolve().parent

LAUNCHES_QS = re.compile(r'"qs"')
NESTS = "nested_display"

# Harnesses that name `qs` only in an assertion about the shell's own source,
# and start nothing. Verified by hand; the check below also requires that they
# contain no subprocess launch of qs, so a file that starts launching one
# cannot hide here.
SOURCE_ONLY = frozenset({
    "test_conflict_killer_contract.py",
})


def launches_qs(tree):
    """Whether any argv list literal in the file carries `qs` as argv[0].

    A string assertion about the shell's source ('["qs", "-p", ...]' in text)
    is not a launch, which is why this asks the syntax tree for a list whose
    FIRST element is the binary rather than grepping for the name.
    """
    for node in ast.walk(tree):
        if not isinstance(node, (ast.List, ast.Tuple)) or not node.elts:
            continue
        first = node.elts[0]
        if isinstance(first, ast.Constant) and first.value == "qs":
            return True
        # `dbus-run-session -- qs ...`
        strings = [e.value for e in node.elts
                   if isinstance(e, ast.Constant) and isinstance(e.value, str)]
        if "dbus-run-session" in strings and "qs" in strings:
            return True
    return False


def delegates_to_nested_probe(text):
    """Whether the harness hands off to a `run_*_probe.sh` that nests weston.

    Five harnesses do exactly that - the Python side drives, the shell script
    owns the compositor - and the isolation is real, one level down. Resolved
    by READING the script it names rather than by allowlisting the harness, so
    a probe that stops nesting takes its callers red with it.
    """
    isolated = False
    for name in set(re.findall(r"run_[a-z0-9_]*probe\.sh", text)):
        script = TESTS / name
        if not script.exists():
            return False
        if "weston" not in script.read_text(encoding="utf-8"):
            return False
        isolated = True
    return isolated


def calls_nested_display(tree):
    """Whether the harness actually CALLS the helper, not merely imports it.

    A first version searched the text for the module's name, and a planted
    mutation - the call replaced by `dict(os.environ)`, the import left in
    place - sailed through it. An import is not isolation; the call is. Same
    hole the bus-isolation lint had, found the same way.
    """
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        function = node.func
        if (isinstance(function, ast.Attribute)
                and isinstance(function.value, ast.Name)
                and function.value.id == NESTS
                and function.attr in ("start", "session")):
            return True
    return False


def starts_weston(tree):
    """Whether the file launches its own compositor rather than importing the
    helper that does. Both are isolation; only the spelling differs."""
    for node in ast.walk(tree):
        if not isinstance(node, (ast.List, ast.Tuple)) or not node.elts:
            continue
        first = node.elts[0]
        if isinstance(first, ast.Constant) and first.value == "weston":
            return True
    return False


def main() -> int:
    failures = []
    scanned = 0

    for path in sorted(TESTS.glob("test_*.py")):
        text = path.read_text(encoding="utf-8")
        try:
            tree = ast.parse(text)
        except SyntaxError:
            continue
        if not launches_qs(tree):
            continue
        scanned += 1
        if path.name in SOURCE_ONLY:
            failures.append(
                f"{path.name}: listed as source-only and yet builds a `qs` argv "
                f"list. Drop it from SOURCE_ONLY and nest a display.")
            continue
        if (not calls_nested_display(tree) and not starts_weston(tree)
                and not delegates_to_nested_probe(text)):
            failures.append(
                f"{path.name}: launches `qs` without nesting a compositor, so "
                f"its windows open on the developer's screen - and a layer "
                f"surface there covers it. Take the display from "
                f"`nested_display.start(self, \"<name>\")`.")

    for name in sorted(SOURCE_ONLY):
        if not (TESTS / name).exists():
            failures.append(f"{name}: in SOURCE_ONLY and no longer present.")

    if not scanned:
        failures.append("no qs-launching harness found - the sweep covers nothing")

    for failure in failures:
        print(f"display isolation: {failure}", file=sys.stderr)
    if failures:
        return 1
    print(f"Display isolation lint passed: {scanned} qs harnesses, all nested")
    return 0


if __name__ == "__main__":
    sys.exit(main())
