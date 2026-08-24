#!/usr/bin/env python3
"""`pgrep -f` / `pkill -f` match against the whole command line, including the
command line of the shell that is running them.

`pkill -f "qs -c imi"` kills the shell *and* the process that invoked it, because
that invoking command line contains the pattern. In this repo that has bitten
twice in the same way: an agent restarting the shell killed its own tool process
mid-run, once truncating a file copy so a half-deployed config was left behind.
AGENT.md documented the pattern too, which is how it kept being copied.

The fixes, in order of preference:

  * `pgrep -x <name>` / `pkill -x <name>` - match the executable name exactly.
    This is what the repo already requires of the conflict killer, whose test
    spells out "killall matches on exact process name; no regex/substring
    matching like a pkill -f".
  * the bracket trick - `pkill -f '[m]pvpaper'` - when `-f` is genuinely needed
    to match on arguments. The pattern no longer matches its own literal text,
    so the invoking command line is excluded.

`switchwall.sh` already used the bracket trick on one line and the bare form on
the line above it, which is the sort of inconsistency a check fixes permanently
and a note does not.
"""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[3]

SUFFIXES = {".sh", ".bash", ".py", ".qml", ".lua", ".md"}
# `.claude` holds agent-tooling state, including worktree snapshots of the
# whole repo at older commits - stale copies of files since fixed, which this
# sweep would otherwise report as live regressions and fail the suite on a
# machine whose checkout is clean.
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".cache", ".claude"}
# Frozen historical records. Two of the plan documents warn about this exact
# trap and quote the bad pattern to do so, which is not a defect to fix - it is
# the evidence that a note was not enough.
SKIP_PATHS = ("docs/superpowers/plans/", "docs/superpowers/specs/")

# `pgrep`/`pkill` with -f anywhere in the option cluster, capturing the rest of
# the line so the pattern argument can be inspected.
INVOCATION = re.compile(r"\b(pgrep|pkill)\b((?:\s+-[^\s]+)*)\s+(.+)")

# A bracketed character class anywhere in the pattern makes it self-excluding.
BRACKET_TRICK = re.compile(r"\[[^\]]+\]")

SELF = Path(__file__).name


def offending_lines(path: Path):
    """Yield real invocations. In Markdown only fenced blocks count: prose that
    warns about `pkill -f` has to be able to name the thing it is warning about,
    and this file's own AGENT.md entry does exactly that."""
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return
    markdown = path.suffix == ".md"
    fenced = False
    for number, line in enumerate(text.splitlines(), start=1):
        if markdown and line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if markdown and not fenced:
            continue
        match = INVOCATION.search(line)
        if not match:
            continue
        options, remainder = match.group(2), match.group(3)
        if "-f" not in options:
            continue
        if BRACKET_TRICK.search(remainder):
            continue
        yield number, line.strip()


def main() -> int:
    failures = []
    for path in sorted(REPO.rglob("*")):
        if not path.is_file() or path.suffix not in SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if any(str(path.relative_to(REPO)).startswith(p) for p in SKIP_PATHS):
            continue
        if path.name == SELF:
            continue
        for number, line in offending_lines(path):
            failures.append(
                f"{path.relative_to(REPO)}:{number}: {line}\n"
                f"    `-f` matches the invoking process's own command line. Use `-x <name>`, "
                f"or the bracket trick if matching on arguments is required.")

    if failures:
        print("Self-matching process patterns found:\n", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print("Process pattern lint passed: no pgrep/pkill -f can match its own caller")
    return 0


if __name__ == "__main__":
    sys.exit(main())
