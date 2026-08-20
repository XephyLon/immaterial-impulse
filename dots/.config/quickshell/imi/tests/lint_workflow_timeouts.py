#!/usr/bin/env python3
#
# Regression guard: every workflow job declares a `timeout-minutes`.
#
# A job without one runs until GitHub's own six-hour limit kills it. That is
# not a slow test - the suite finishes in about two and a half minutes - it is
# a runner held for six hours, and on a repository with one concurrent runner
# every other PR queues behind it.
#
# Measured rather than supposed: run 32276396125 on 2be6995c9 ("release:
# 0.27.0") sat on `Install Qt6 Dependencies` from 16:31 to 22:32 and was
# cancelled by the limit, and most of an eighteen-PR series that same day spent
# longer waiting for a runner than being tested. Every observed wedge was apt
# against a mirror, never the suite itself, which is why the install step
# carries its own tighter ceiling and a bounded retry.
#
# A ceiling is not a guess about how long the work takes - it is the answer to
# "how long should this be allowed to hold the queue while broken". Ten times
# the normal run is a generous ceiling and still fails within the hour.
#
# The check is deliberately textual rather than PyYAML: this suite runs with
# whatever python3 the machine has, PyYAML is not a declared dependency of the
# shell, and a check that silently skips when an import fails is the failure
# mode `run_tests.sh` already had three of.
#
# Exits non-zero listing jobs with no ceiling. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

# tests/ sits five levels under the repo root.
REPO = Path(__file__).resolve().parents[5]
WORKFLOWS = REPO / ".github" / "workflows"

JOB = re.compile(r"^  (?P<name>[A-Za-z0-9_-]+):\s*$")
TIMEOUT = re.compile(r"^    timeout-minutes:\s*(\d+)\s*$")
# A step's own ceiling is indented deeper and is not the job's.
ANY_KEY_AT_JOB_LEVEL = re.compile(r"^  \S")


def jobs_without_ceiling(text: str):
    """(job, declared) for every job in one workflow file.

    Read line by line against indentation rather than parsed: the shape being
    checked is two levels deep and fixed by the schema, and this keeps the
    check free of a dependency the rest of the suite does not have.
    """
    lines = text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.rstrip() == "jobs:")
    except StopIteration:
        return []

    found = []
    current, ceiling = None, None
    for line in lines[start + 1:]:
        if line.strip() and not line.startswith(" "):
            break  # a new top-level key: jobs: is over
        match = JOB.match(line)
        if match:
            if current is not None:
                found.append((current, ceiling))
            current, ceiling = match.group("name"), None
            continue
        if current is not None and TIMEOUT.match(line):
            ceiling = int(TIMEOUT.match(line).group(1))
    if current is not None:
        found.append((current, ceiling))
    return found


FIXTURE_UNCAPPED = """name: X
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
"""

FIXTURE_CAPPED = """name: X
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - name: slow
        timeout-minutes: 10
        run: echo hi
  second:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - run: echo hi
"""


def self_check():
    """Prove the reader on fixtures, not on what the tree happens to hold.

    The second fixture is the one that earns its place: a step's own
    `timeout-minutes` is indented deeper than a job's, and a check that
    matched it anywhere would read a capped step as a capped job and pass a
    workflow that can still run for six hours.
    """
    problems = []
    if jobs_without_ceiling(FIXTURE_UNCAPPED) != [("build", None)]:
        problems.append("self-check: an uncapped job was not reported")
    if jobs_without_ceiling(FIXTURE_CAPPED) != [("build", 25), ("second", 5)]:
        problems.append("self-check: a capped job or its step ceiling was misread")
    return problems


def main() -> int:
    failures = self_check()

    if not WORKFLOWS.is_dir():
        print(f"workflow timeouts: {WORKFLOWS} does not exist - the check is "
              f"looking in the wrong place", file=sys.stderr)
        return 1

    files = sorted(WORKFLOWS.glob("*.yml")) + sorted(WORKFLOWS.glob("*.yaml"))
    if not files:
        failures.append("no workflow files found - the sweep covers nothing")

    checked = 0
    for path in files:
        for job, ceiling in jobs_without_ceiling(path.read_text(encoding="utf-8")):
            checked += 1
            if ceiling is None:
                failures.append(
                    f"{path.name}: job `{job}` declares no timeout-minutes. A "
                    f"wedged step then holds a runner until GitHub's six-hour "
                    f"limit and every other PR queues behind it - which is how "
                    f"the 0.27.0 release run spent six hours inside apt.")

    for failure in failures:
        print(f"workflow timeouts: {failure}", file=sys.stderr)
    if failures:
        return 1
    print(f"Workflow timeout lint passed: {checked} jobs, all with a ceiling")
    return 0


if __name__ == "__main__":
    sys.exit(main())
