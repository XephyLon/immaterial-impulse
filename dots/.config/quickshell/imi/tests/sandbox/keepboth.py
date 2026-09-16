#!/usr/bin/env python3
"""Resolve conflict hunks in FILE by keeping OURS then THEIRS (additive files:
CHANGELOG, AGENT.md, run_tests.sh, index arrays). Prints the hunk count."""
import re, sys
path = sys.argv[1]
text = open(path).read()
pat = re.compile(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", re.S)
n = 0
def rep(m):
    global n; n += 1
    ours, theirs = m.group(1), m.group(2)
    if ours.strip() == theirs.strip():
        return ours
    return ours + theirs
out = pat.sub(rep, text)
open(path, "w").write(out)
print(f"{path}: {n} hunk(s) kept both")
