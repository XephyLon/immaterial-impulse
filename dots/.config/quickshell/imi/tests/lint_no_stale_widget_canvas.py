#!/usr/bin/env python3
#
# Regression guard: there is ONE desktop-widget base class, and it lives in
# `modules/common/widgets/widgetCanvas/`.
#
# The vendored design system arrived carrying its own copy of
# `AbstractWidget.qml` and `WidgetCanvas.qml`. Nothing imported them - not one
# QML file names `qs.modules.common.plugins.designsystem.widgets.widgetCanvas`,
# and `PluginWidget`, `AbstractBackgroundWidget` and the canvas itself all
# resolve the mainline types - so the copy was dead the day it landed and
# stayed dead through every fix the live one took.
#
# The cost is not the duplication. It is that the dead copy still carried the
# `MouseArea.drag` + `dragProxy { x: root.x }` pair that d2ebb5aeb
# ("fix(widgetCanvas): compute the drag by hand - MouseArea.drag cannot track
# it") removed for measured reasons, gated on a config path that does not
# exist, three fixes behind - and it reads as the RICHER implementation. The
# next agent looking for how the drag works finds a plausible file with more
# snap code in it and no way to tell that it never runs.
# (docs/p3drovfx-animation-research-2026-08-16.md §7, finding 2.)
#
# So: no second file may declare either type name outside the one directory.
# A copy that is imported is caught by the import check below as well, but the
# point is to fail on it while it is still dead, which is the state nothing
# else in the suite can see.
#
# Exits non-zero. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OWNER = "modules/common/widgets/widgetCanvas"
TYPES = ("AbstractWidget.qml", "WidgetCanvas.qml", "AbstractOverlayWidget.qml")
# The module path the deleted copy would have been reached by, in QML's dotted
# import form and in the URL form a `Loader` would use.
DEAD_IMPORT = re.compile(
    r"qs\.modules\.common\.plugins\.designsystem\.widgets\.widgetCanvas"
    r"|designsystem/widgets/widgetCanvas")


def main() -> int:
    failures = []

    owner = ROOT / OWNER
    if not owner.is_dir():
        failures.append(f"{OWNER}/ is gone - the base class moved without this check")
    else:
        present = {path.name for path in owner.glob("*.qml")}
        for name in ("AbstractWidget.qml", "WidgetCanvas.qml"):
            if name not in present:
                failures.append(f"{OWNER}/{name} is missing")

    for path in sorted(ROOT.rglob("*.qml")):
        relative = path.relative_to(ROOT).as_posix()
        if relative.startswith("tests/") or relative.startswith(OWNER + "/"):
            continue
        if path.name in TYPES:
            failures.append(
                f"{relative}: a second `{path.name}`. The desktop-widget base "
                f"class lives in {OWNER}/ and nowhere else - a copy is dead on "
                f"arrival and reads as the richer implementation, which is how "
                f"the design system's dup kept a drag idiom d2ebb5aeb removed.")

    for path in sorted(ROOT.rglob("*.qml")):
        relative = path.relative_to(ROOT).as_posix()
        if relative.startswith("tests/"):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        if DEAD_IMPORT.search(text):
            failures.append(
                f"{relative}: imports the design system's widgetCanvas, which "
                f"does not exist. The types come from {OWNER}/.")

    for failure in failures:
        print(f"stale widget canvas: {failure}", file=sys.stderr)
    if failures:
        return 1
    print("Stale widget canvas lint passed: one AbstractWidget, one WidgetCanvas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
