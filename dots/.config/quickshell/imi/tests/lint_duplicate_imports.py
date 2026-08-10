#!/usr/bin/env python3
"""A QML file may not import the same script qualifier twice.

`import "../functions/parallax.js" as ParallaxMath` twice in one file is a hard
load error — *Script import qualifiers must be unique* — and it takes the whole
shell down with it: the failure cascades from `shell.qml` through the panel
family to the file that actually broke, and the user gets no panels at all.

It reached `main` through a rebase conflict resolution: two branches each added
an import to the same block, the resolution kept both sides of the marker, and
one line was already present above. Nothing caught it —

- `qmltestrunner` never loads `PluginWidget.qml`; it cannot construct Quickshell
  types.
- `DesignSystemCompile.qml` *does* list the file, and still reported
  `failures=0`.

so CI was green on a tree whose shell could not start. That is the gap this
closes, and it is worth closing statically because the answer needs no
compositor, no shell, and no Qt: it is one pass over the import block.
"""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", "__pycache__", "tests"}

# `import "x.js" as Name` — only script imports take a qualifier this way, and
# only they can collide. Module imports (`import QtQuick`) are not affected.
SCRIPT_IMPORT = re.compile(r'^\s*import\s+"([^"]+)"\s+as\s+(\w+)', re.M)


def failures_for(path: Path):
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return []

    out = []
    by_qualifier = {}
    for match in SCRIPT_IMPORT.finditer(text):
        source, qualifier = match.group(1), match.group(2)
        line = text.count("\n", 0, match.start()) + 1
        if qualifier in by_qualifier:
            first_line, first_source = by_qualifier[qualifier]
            same = " (the identical line)" if first_source == source else ""
            out.append(
                f"{path.relative_to(ROOT)}:{line}: qualifier {qualifier!r} is already "
                f"bound at line {first_line}{same}. Qt refuses the file and the shell "
                f"fails to load with no panels.")
        else:
            by_qualifier[qualifier] = (line, source)
    return out


def main() -> int:
    failures = []
    for path in sorted(ROOT.rglob("*.qml")):
        if any(part in SKIP_DIRS for part in path.relative_to(ROOT).parts):
            continue
        failures.extend(failures_for(path))

    if failures:
        print("Duplicate script import qualifiers:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print("Import lint passed: no file binds a script qualifier twice")
    return 0


if __name__ == "__main__":
    sys.exit(main())
