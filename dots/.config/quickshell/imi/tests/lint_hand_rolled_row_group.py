#!/usr/bin/env python3
"""A group of related rows is a `GroupedList`, never a rectangle of one's own.

docs/M3_GUIDELINES.md, "Grouped Settings": *use the standard `GroupedList`
presentation when rows are related but remain visually distinct.* The phone
roster broke that rule the day it was written - a `StyledRectangle` wrapped
around a `StyledListView` of `DialogListItem` rows - and the reason it was
caught is that it LOOKED wrong: `clip` on a Rectangle clips to the bounding
box and not to the radius, so the opaque rows painted straight over the four
rounded corners the wrapper thought it had. The runtime check written
alongside it asked that wrapper for its `radius`, was told 17, and passed
while the screen showed a perfect rectangle.

Two rules were already written down and still broken, so this is the third
spelling and the one that fails: the prose in M3_GUIDELINES.md, the component
itself, and now a check.

Scope, deliberately narrow enough to have no false positives to argue with: a
rectangle that CONTAINS a list of rows, where a row is a component this repo
roots on `DialogListItem`. That is the shape of the mistake. A rectangle
holding one row, a list of something that is not a row, or `GroupedList`'s own
plates (a Rectangle around a Loader) are all left alone.
"""

import pathlib
import re
import sys

SHELL = pathlib.Path(__file__).resolve().parent.parent
RECTANGLES = ("Rectangle", "StyledRectangle")
LISTS = ("ListView", "StyledListView", "Repeater")
# GroupedList builds the plates this lint would otherwise report; it is the
# component the rule points AT.
EXEMPT = {"GroupedList.qml"}

# The type a `{` opens is the last identifier before it, which is what makes
# `delegate: PhoneDeviceItem {` read as a PhoneDeviceItem rather than as a
# property assignment. The first spelling of this lint matched on the text
# BEFORE the colon and reported a clean tree over the very file it was written
# for, so the name is taken from the brace backwards now.
TYPE_BEFORE_BRACE = re.compile(r"([A-Za-z_][\w.]*)\s*$")


def row_types() -> set:
    """Every component in this shell whose root type is `DialogListItem`."""
    found = {"DialogListItem"}
    # A row type may itself be subclassed, so settle it rather than
    # single-pass: PhoneDeviceItem is a DialogListItem, and anything rooted on
    # PhoneDeviceItem is a row too.
    changed = True
    while changed:
        changed = False
        for path in SHELL.rglob("*.qml"):
            if path.stem in found:
                continue
            for line in path.read_text(errors="replace").splitlines():
                stripped = line.strip()
                if not stripped or stripped.startswith(("//", "*", "/*", "import", "pragma")):
                    continue
                root = stripped.split("{")[0].strip()
                if root in found:
                    found.add(path.stem)
                    changed = True
                break
    return found


def offenders(path: pathlib.Path, rows: set) -> list:
    """Rows opened while both a list and a rectangle are on the stack."""
    stack = []
    hits = []
    for number, line in enumerate(path.read_text(errors="replace").splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        for position, char in enumerate(stripped):
            if char == "{":
                match = TYPE_BEFORE_BRACE.search(stripped[:position])
                name = match.group(1) if match else ""
                if name in rows and any(n in LISTS for n in stack) \
                        and any(n in RECTANGLES for n in stack):
                    hits.append((number, name))
                stack.append(name)
            elif char == "}" and stack:
                stack.pop()
    return hits


def main() -> int:
    rows = row_types()
    failures = []
    for path in sorted(SHELL.rglob("*.qml")):
        if path.name in EXEMPT or "/tests/" in str(path):
            continue
        for number, row in offenders(path, rows):
            failures.append(f"{path.relative_to(SHELL)}:{number}: "
                            f"`{row}` rows wrapped in a rectangle of their own")
    if failures:
        print("A group of related rows is a GroupedList, not a hand-rolled surface")
        print("(docs/M3_GUIDELINES.md, \"Grouped Settings\"). Offenders:")
        for failure in failures:
            print(f"  {failure}")
        return 1
    print(f"  hand-rolled row groups: none ({len(rows)} row types known)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
