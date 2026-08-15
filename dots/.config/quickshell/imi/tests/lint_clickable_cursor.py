#!/usr/bin/env python3
#
# Regression guard: a bar widget that acts on a click says so with the pointer.
#
# The bar is a row of shapes with no affordances of their own - a pill, an icon,
# a number - so the only thing distinguishing "this opens a panel" from "this is
# a readout" before you click is the cursor. Half the bar acted on clicks while
# leaving the arrow alone: the privacy pill, the tray icons, the media pill, the
# weather, the system icons, the timer and the util buttons. The shared button
# types (`RippleButton`, `ButtonMouseArea`) had always set it; the raw
# `MouseArea`s written per widget each forgot separately, which is the shape of
# a rule that has to be mechanised rather than remembered.
#
# The rule: a MouseArea in the bar that has a click handler and responds to a
# PRIMARY click sets `cursorShape`. Areas that take no buttons
# (`Resource` hovers a popup with `Qt.NoButton`) and areas listening only for
# back/right over a whole surface (`SysTrayMenu`'s go-back gesture) are exempt
# and must stay exempt: a hand cursor over something that does not answer a left
# click is its own lie.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BAR = ROOT / "modules" / "imi" / "bar"

CLICK_HANDLER = re.compile(r"\bon(Clicked|Pressed|Released|DoubleClicked)\b")
ACCEPTED = re.compile(r"acceptedButtons\s*:\s*([^\n]+)")


def mouse_area_blocks(text):
    """Yield (start_line, block_text) for each MouseArea body, by brace depth."""
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if not re.search(r"\bMouseArea\s*\{", line):
            continue
        depth = 0
        body = []
        for cursor in range(index, len(lines)):
            current = lines[cursor]
            body.append(current)
            depth += current.count("{") - current.count("}")
            if depth <= 0 and cursor > index:
                break
            if depth <= 0 and cursor == index and current.count("}") >= current.count("{"):
                break
        yield index + 1, "\n".join(body)


def main():
    offenders = []
    for path in sorted(BAR.glob("*.qml")):
        text = path.read_text()
        for line_number, block in mouse_area_blocks(text):
            if not CLICK_HANDLER.search(block):
                continue
            accepted = ACCEPTED.search(block)
            if accepted and "LeftButton" not in accepted.group(1):
                # Hover-only (Qt.NoButton), or a gesture catcher listening for
                # back/right over a whole surface. Neither is a button, and a
                # hand cursor over something that does not respond to a primary
                # click is its own lie.
                continue
            if "cursorShape" in block:
                continue
            offenders.append(f"{path.relative_to(ROOT)}:{line_number}: "
                             "clickable MouseArea without cursorShape")

    if offenders:
        print("Clickable bar widgets that leave the pointer as an arrow:")
        for offender in offenders:
            print(f"  {offender}")
        print("\nSet `cursorShape: Qt.PointingHandCursor`, or "
              "`acceptedButtons: Qt.NoButton` if it is hover-only.")
        return 1

    print("[lint_clickable_cursor] every clickable bar MouseArea sets a cursor")
    return 0


if __name__ == "__main__":
    sys.exit(main())
