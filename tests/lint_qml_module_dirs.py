#!/usr/bin/env python3
#
# Regression guard: a directory reached by a relative QML directory import has
# to be named like a QML module segment.
#
# `import "../plugins/bundled/discord-voice" as Pkg` makes Quickshell's scanner
# read the directory name as a module name. A hyphen is not legal there, so it
# logs
#
#   WARN quickshell.qmlscanner: Module path contains invalid characters for a
#   module name: "/modules/common/plugins/bundled/discord-voice"
#
# on every scan. The import still resolves, which is why this survives review:
# nothing breaks, the log just fills up on each reload.
#
# Only directories that are actually imported this way are checked. Plenty of
# hyphenated directories are fine because they are loaded dynamically by path
# (the `nandoroid-*` plugin ports), and renaming those would fight their
# upstream naming for no benefit.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# `import "some/dir" as Alias` - quoted, not ending in a file extension.
DIR_IMPORT = re.compile(r'^\s*import\s+"([^"]+)"(?:\s+as\s+\w+)?\s*$')
SEGMENT = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')

# tests/imports and tests/mocks are symlink farms pointing back at the real
# sources, so scanning them would double-report and trip over dangling links.
SKIP = {".git", "node_modules"}
SKIP_RELATIVE = {os.path.join("tests", "imports"), os.path.join("tests", "mocks")}

violations = []
for base, dirs, files in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d not in SKIP]
    relative_base = os.path.relpath(base, ROOT)
    if any(relative_base == skip or relative_base.startswith(skip + os.sep)
           for skip in SKIP_RELATIVE):
        dirs[:] = []
        continue
    for name in files:
        if not name.endswith(".qml"):
            continue
        path = os.path.join(base, name)
        rel = os.path.relpath(path, ROOT)
        if not os.path.isfile(path):
            continue
        with open(path) as handle:
            for number, line in enumerate(handle, 1):
                match = DIR_IMPORT.match(line)
                if not match:
                    continue
                target = match.group(1)
                if target.endswith((".qml", ".js", ".mjs")):
                    continue
                for segment in target.split("/"):
                    if segment in ("", ".", ".."):
                        continue
                    if not SEGMENT.match(segment):
                        violations.append((rel, number, target, segment))

if violations:
    print("QML module directory lint FAILED: directories reached by a relative "
          "directory import must be named like a QML module segment "
          "(letters, digits and underscore; no hyphens):", file=sys.stderr)
    for rel, number, target, segment in violations:
        print(f"  {rel}:{number}  import \"{target}\"  -> invalid segment {segment!r}",
              file=sys.stderr)
    sys.exit(1)

print("QML module directory lint passed: relative directory imports use valid module names")
sys.exit(0)
