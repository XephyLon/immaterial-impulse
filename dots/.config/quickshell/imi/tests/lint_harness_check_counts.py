#!/usr/bin/env python3
"""A harness verdict states how many checks ran, and its driver asserts the number.

Every runtime harness used to end with `failures: ${harness.failures}` and
every driver with `assertIn("[Tag] failures: 0", output)`. Nothing in that
pair distinguishes "every check passed" from "no check ran": a loop that stops
iterating, a step array that loses an entry, or an early return past the rest
of the list all print `failures: 0` and pass. Seven of the ten shipped
instances in the integration-testing spec's catalogue are that shape - none of
them reddened, they went quiet.

So the convention, and what this lint holds:

  - a harness that prints a `failures:` verdict prints `checks:` in the same
    line, from a counter incremented inside its own `check()` - the number has
    to be what ran, not what was written, or a harness that gives up early
    still reports the full count;
  - a driver asserting that verdict carries the expected count as an
    interpolated literal. A count read back out of the harness's own output
    would agree with itself by construction, which is instance #4 in that same
    catalogue - an assertion that is the subject, spelled twice.

The self-check below runs first, on fixtures held in this file, so the
machinery is proven independently of what the tree happens to contain.

Run from `tests/run_tests.sh`.
docs/superpowers/specs/2026-08-14-integration-testing-design.md §3 D1.
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHELL_ROOT = HERE.parent

VERDICT = re.compile(r"console\.log\(`\[([^\]]+)\][^`]*failures:[^`]*`\)")
CHECK_BODY = re.compile(r"\n(\s*)function check\(.*?\n\1\}", re.DOTALL)
# The literal the driver asserts, e.g. `[DockEdge] checks: {EXPECTED_CHECKS}
# failures: 0`. Only the assertion strings matter; a docstring naming the old
# shape is prose.
DRIVER_ASSERT = re.compile(r"assertIn\(\s*(f?)(['\"])(.*?)\2", re.DOTALL)


def harness_offences(source):
    verdicts = VERDICT.findall(source)
    if not verdicts:
        return []

    offences = []
    for whole in re.findall(r"console\.log\(`\[[^\]]+\][^`]*failures:[^`]*`\)", source):
        if "checks:" not in whole:
            offences.append(
                "prints a failures: verdict with no check count, so an empty run "
                "reads exactly like a clean one")
        elif not re.search(r"checks: \$\{[^}]*checksRun\}", whole):
            offences.append(
                "prints a check count that is not the live counter; a constant "
                "here is printed whether or not the checks ran")

    if "property int checksRun: 0" not in source:
        offences.append("declares no checksRun counter")

    body = CHECK_BODY.search(source)
    if not body:
        offences.append("has no check() to count from")
    elif "checksRun++" not in body.group(0):
        offences.append(
            "does not increment checksRun inside check(); counted anywhere else, "
            "the number stops being the number of checks that ran")
    return offences


def driver_offences(source):
    offences = []
    for prefix, _quote, literal in DRIVER_ASSERT.findall(source):
        if "failures: 0" not in literal:
            continue
        if "checks: " not in literal:
            offences.append(
                f"asserts {literal.strip()!r}, which a harness that ran nothing "
                "also satisfies")
        elif not (prefix == "f" and re.search(r"checks: \{[^}]+\}", literal)):
            offences.append(
                f"asserts {literal.strip()!r} with the count spelled into the "
                "assertion string; it belongs in a named module-level constant, "
                "where whoever next changes the harness will see it")
    return offences


GOOD_HARNESS = """
    property int failures: 0
    property int checksRun: 0

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[Fixture] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[Fixture] checks: ${harness.checksRun} failures: ${harness.failures}`);
    }
"""

FIXTURES = [
    ("a harness with no count at all",
     harness_offences, GOOD_HARNESS.replace("checks: ${harness.checksRun} ", ""), True),
    ("a harness printing a constant count",
     harness_offences, GOOD_HARNESS.replace("${harness.checksRun}", "12"), True),
    ("a harness counting outside check()",
     harness_offences, GOOD_HARNESS.replace("        harness.checksRun++;\n", ""), True),
    ("a harness with no counter declared",
     harness_offences, GOOD_HARNESS.replace("    property int checksRun: 0\n", ""), True),
    ("a correct harness", harness_offences, GOOD_HARNESS, False),
    ("a driver asserting failures alone", driver_offences,
     'self.assertIn("[Fixture] failures: 0", output, "msg")', True),
    ("a driver hardcoding the count", driver_offences,
     'self.assertIn("[Fixture] checks: 7 failures: 0", output, "msg")', True),
    ("a correct driver", driver_offences,
     'self.assertIn(f"[Fixture] checks: {EXPECTED_CHECKS} failures: 0", output, "msg")', False),
]


def self_check():
    broken = []
    for name, rule, fixture, should_fire in FIXTURES:
        fired = bool(rule(fixture))
        if fired != should_fire:
            broken.append(f"{name}: expected fired={should_fire}, got {fired}")
    return broken


def main():
    broken = self_check()
    if broken:
        print("Harness check-count lint is broken - its own fixtures disagree "
              "with it:", file=sys.stderr)
        for line in broken:
            print(f"  {line}", file=sys.stderr)
        return 1

    failures = []
    harnesses = 0
    for path in sorted(SHELL_ROOT.glob("*.qml")):
        source = path.read_text(encoding="utf-8")
        if not VERDICT.search(source):
            continue
        harnesses += 1
        for offence in harness_offences(source):
            failures.append(f"{path.name}: {offence}")

    drivers = 0
    for path in sorted(HERE.glob("test_*.py")):
        source = path.read_text(encoding="utf-8")
        offences = driver_offences(source)
        if "failures: 0" in source:
            drivers += 1
        for offence in offences:
            failures.append(f"tests/{path.name}: {offence}")

    if failures:
        print("Harness check-count lint FAILED:", file=sys.stderr)
        for line in failures:
            print(f"  {line}", file=sys.stderr)
        return 1

    print(f"Harness check-count lint passed "
          f"({harnesses} harness verdicts, {drivers} drivers)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
