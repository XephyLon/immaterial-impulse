#!/usr/bin/env python3
#
# Regression guard: every compositor-nesting harness runs inside the suite lock.
#
# `run_tests.sh` takes one exclusive `flock` before its first runtime harness
# and holds it to the end of the run, so two suites started in two git
# worktrees cannot have their nested westons up at the same time. That
# collision is not a red test - it is `The Wayland connection broke. Did the
# Wayland compositor die?` in whichever run lost, which reads exactly like a
# regression in the code under test and has cost three full re-runs and one
# agent "fixing" code that was never broken.
#
# One acquire point is deliberate (the reasoning is written out in
# `run_tests.sh`): forty acquire/release pairs would overlap more and would be
# a rule every future harness has to remember. What makes the single boundary
# safe is that nothing may be wired in above it, and THAT is a rule a check can
# hold. A harness added to the top half of the file would run unprotected,
# silently, and its collisions would look like flakes.
#
# "A harness that nests a compositor" is not a list kept here: it is
# `lint_display_isolation.launches_qs`, the same classifier that already
# decides which harnesses must bring their own display. One definition, so a
# harness cannot be a compositor harness for one check and not the other.
#
# Exits non-zero. Wired into run_tests.sh / CI.

import ast
import sys
from pathlib import Path

import lint_display_isolation

TESTS = Path(__file__).resolve().parent
RUNNER = TESTS / "run_tests.sh"

# The invocation form, never a mention: several blocks name a sibling harness
# in their comment, and a comment above the boundary is not a harness running
# above it.
INVOCATION = 'python3 "$SCRIPT_DIR/{name}"'
ACQUIRE = "acquire_suite_lock"


def acquire_lines(runner: str):
    """Line numbers of the top-level `acquire_suite_lock` call.

    The definition (`acquire_suite_lock() {`) and every mention inside a
    comment are excluded, so the answer is where the lock is actually taken.
    """
    found = []
    for number, line in enumerate(runner.splitlines(), 1):
        stripped = line.strip()
        if stripped == ACQUIRE:
            found.append(number)
    return found


def invocation_lines(runner: str, name: str):
    needle = INVOCATION.format(name=name)
    return [number for number, line in enumerate(runner.splitlines(), 1)
            if needle in line and not line.lstrip().startswith("#")]


def compositor_harnesses():
    """Every `test_*.py` that ends up with a compositor of its own running.

    Three spellings, all of them the sibling lint's: the harness builds a `qs`
    argv itself, it starts weston itself, or it hands off to a `run_*_probe.sh`
    that does (test_edit_mode_chrome.py and test_bar_exclusive_zone_reserver.py
    are the two that delegate, and a check that asked only about `qs` argv
    lists would have placed neither).
    """
    names = []
    for path in sorted(TESTS.glob("test_*.py")):
        text = path.read_text(encoding="utf-8")
        try:
            tree = ast.parse(text)
        except SyntaxError:
            continue
        if (lint_display_isolation.launches_qs(tree)
                or lint_display_isolation.starts_weston(tree)
                or lint_display_isolation.delegates_to_nested_probe(text)):
            names.append(path.name)
    return names


def check(runner: str, harnesses):
    """Failures for one runner text and one set of harness file names."""
    failures = []
    acquires = acquire_lines(runner)
    if not acquires:
        return [f"run_tests.sh never calls {ACQUIRE}: the runtime harnesses "
                f"run unserialized, so a suite in another worktree can break "
                f"this one mid-harness."]
    if len(acquires) > 1:
        failures.append(
            f"run_tests.sh calls {ACQUIRE} {len(acquires)} times (lines "
            f"{', '.join(str(n) for n in acquires)}). One boundary is the "
            f"whole design - a second one means part of the run is outside a "
            f"section that reads as inside it.")
    boundary = acquires[0]

    registered = 0
    for name in harnesses:
        lines = invocation_lines(runner, name)
        if not lines:
            # Not this check's business: lint_suite_registration.py owns
            # "wired in at all", and a harness reached some other way is not
            # something this one can place.
            continue
        registered += 1
        early = [n for n in lines if n < boundary]
        if early:
            failures.append(
                f"{name}: invoked at line {early[0]}, above the "
                f"{ACQUIRE} at line {boundary}. It starts a nested "
                f"compositor, so it has to run inside the lock - move the "
                f"block below the boundary rather than moving the boundary "
                f"up, which would serialize the static lints for nothing.")

    if not registered:
        failures.append(
            "no compositor harness found in run_tests.sh - the sweep covers "
            "nothing, which is what it looks like when the invocation spelling "
            "changes.")
    return failures


GOOD = """\
echo "a static lint"
python3 "$SCRIPT_DIR/lint_spacing.py"
acquire_suite_lock
python3 "$SCRIPT_DIR/test_edit_mode_runtime.py"
"""

EARLY = """\
python3 "$SCRIPT_DIR/test_edit_mode_runtime.py"
acquire_suite_lock
python3 "$SCRIPT_DIR/test_phone_tab_runtime.py"
"""

MENTIONED_ONLY = """\
# test_edit_mode_runtime.py is the sibling of the one below
acquire_suite_lock
python3 "$SCRIPT_DIR/test_edit_mode_runtime.py"
"""

NO_ACQUIRE = """\
python3 "$SCRIPT_DIR/test_edit_mode_runtime.py"
"""

TWICE = """\
acquire_suite_lock
python3 "$SCRIPT_DIR/test_edit_mode_runtime.py"
acquire_suite_lock
"""


def self_check():
    """The check proved against fixtures, independently of the real tree.

    A source-text check is code with nothing testing it, and this repo's
    silent failures are checks that were green over the thing they exist to
    refuse. Each fixture is one way the boundary breaks.
    """
    cases = [
        (GOOD, ["test_edit_mode_runtime.py"], 0, "a harness below the boundary"),
        (EARLY, ["test_edit_mode_runtime.py", "test_phone_tab_runtime.py"], 1,
         "a harness above the boundary"),
        (MENTIONED_ONLY, ["test_edit_mode_runtime.py"], 0,
         "a harness NAMED above the boundary and invoked below it"),
        (NO_ACQUIRE, ["test_edit_mode_runtime.py"], 1, "no boundary at all"),
        (TWICE, ["test_edit_mode_runtime.py"], 1, "two boundaries"),
    ]
    problems = []
    for runner, harnesses, expected, description in cases:
        found = len(check(runner, harnesses))
        if found != expected:
            problems.append(
                f"self-check: {description} produced {found} failures, "
                f"expected {expected}")
    # And the vacuity guard, which is the one that keeps a spelling change
    # from turning this whole lint into a no-op.
    if len(check(GOOD, [])) != 1:
        problems.append("self-check: an empty harness set did not report the "
                        "sweep as covering nothing")
    return problems


def main() -> int:
    problems = self_check()
    for problem in problems:
        print(f"suite lock scope: {problem}", file=sys.stderr)
    if problems:
        return 1

    runner = RUNNER.read_text(encoding="utf-8")
    harnesses = compositor_harnesses()
    failures = check(runner, harnesses)
    for failure in failures:
        print(f"suite lock scope: {failure}", file=sys.stderr)
    if failures:
        return 1

    inside = sum(1 for name in harnesses if invocation_lines(runner, name))
    print(f"Suite lock scope lint passed: {inside} compositor harnesses, all "
          f"inside the lock")
    return 0


if __name__ == "__main__":
    sys.exit(main())
