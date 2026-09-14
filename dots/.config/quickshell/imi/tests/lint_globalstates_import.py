#!/usr/bin/env python3
"""A QML file that names `GlobalStates.` must import the module that holds it.

GlobalStates.qml is the shell root's singleton: it resolves through `import qs`
or a relative import that reaches the root (`import ".."`, `"../.."`, ...).
Without one the name is a ReferenceError at binding time - a WARNING, not a
load failure - so a whole mechanism can be inert while every load gate is
green (services/FrameGeometry.qml's dock occupant was, for one review round).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN = ("services", "modules", "panelFamilies")


def strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def resolves_root(path, text):
    if re.search(r"^import qs\s*$", text, re.M):
        return True
    # A relative import of any directory that holds a GlobalStates.qml
    # (the shell root, or the design system's own shim beside its gallery).
    for m in re.finditer(r'^import "([^"]+)"', text, re.M):
        target = (path.parent / m.group(1)).resolve()
        if (target / "GlobalStates.qml").is_file():
            return True
    return (path.parent / "GlobalStates.qml").is_file()


def main():
    bad = []
    for d in SCAN:
        for f in sorted((ROOT / d).rglob("*.qml")):
            text = strip(f.read_text(encoding="utf-8", errors="replace"))
            if "GlobalStates." not in text:
                continue
            if not resolves_root(f, text):
                bad.append(f.relative_to(ROOT).as_posix())
    if bad:
        print("These name GlobalStates. and import neither `qs` nor a path to the shell root:")
        for b in bad:
            print("  " + b)
        return 1
    print("GlobalStates import: every consumer can resolve it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
