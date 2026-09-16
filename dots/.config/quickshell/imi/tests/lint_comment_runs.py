#!/usr/bin/env python3
"""A prose comment is not split by a blank line.

Twice in one branch an edit helper kept a heredoc's trailing newline and
dropped a blank line into the middle of a `//` comment (GlobalStates.qml -
where the same slip also broke a line and the whole shell failed to load -
and dock_geometry.js). A reviewer found the second one; the rule is that a
mistake made twice becomes a check.

A hit is a `//` prose line that ends mid-sentence (no terminal punctuation),
a blank line, then a `//` line that continues in lower case. Commented-out
code (`//` followed by indentation), separators (`// ----`) and comment
lines that start a new thought (`// options.key`) are not prose runs and
are left alone. Nothing is allowlisted: fix the comment.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP = ("/tests/", "/plugins/designsystem/", "/node_modules/")
PROSE = re.compile(r"^\s*//\s(?!\s)(?P<text>.*\S)\s*$")
CONTINUES = re.compile(r"^\s*//\s(?P<word>[a-z][a-z']*)\s")
ENDS = re.compile(r"[.:!?)\]\"'`]$")


def hits(path):
    lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
    out = []
    for i in range(1, len(lines) - 1):
        if lines[i].strip():
            continue
        a, b = PROSE.match(lines[i - 1]), CONTINUES.match(lines[i + 1])
        if not a or not b:
            continue
        text = a.group("text")
        if ENDS.search(text) or "----" in text or "====" in text:
            continue
        out.append(f"{path.relative_to(ROOT)}:{i + 1}: comment split by a blank line after '...{text[-40:]}'")
    return out


def main():
    problems = []
    for pattern in ("**/*.qml", "**/*.js"):
        for path in sorted(ROOT.glob(pattern)):
            if any(s in str(path) for s in SKIP):
                continue
            problems.extend(hits(path))
    if problems:
        print("\n".join(problems))
        print(f"{len(problems)} split comment(s): join the run, or end the first part with a full stop.")
        return 1
    print("Comment runs: no prose comment is split by a blank line")
    return 0


if __name__ == "__main__":
    sys.exit(main())
