#!/usr/bin/env python3
"""A drag that reorders a list does it through `layout_ops.js`, not by hand.

Four surfaces reorder a list by dragging one of its items - the bar's chip
editor (`LayoutSection.qml`), the dock strip (`DragApps.qml`), the bar's copy of
that strip (`DocktoPanel.qml`) and the Android quick toggles
(`AndroidQuickToggleButton.qml`) - and all four had written the arithmetic out
locally. The duplication was not the defect. The disagreement was: two of them
took the dragged item out and put it back at the drop index, so everything
between shifted one place along, and two exchanged the two entries, so a drag
across three neighbours displaced exactly one of them. Both spell the same list
for a step of one, which is why nobody saw it: on a slow drag every call site
reorders one slot at a time.

Four copies of an answer is how three of them go stale, so what is checked here
is that a fifth cannot appear quietly - the same reasoning as
`tests/test_cava_contract.py`'s one-producer rule and
`lint_bar_popup_overlay_static.py`'s one-derivation rule for `barEdge`.

The scope comes from the tree rather than from a list of file names: a QML file
that declares a `DragHandler` is a file where something is dragged, and those
are the files a reorder can appear in. Inside one, three idioms are refused:

  * a splice-out immediately followed by a splice-in - `move`, spelled locally;
  * an indexed element exchange (`t = a[i]; a[i] = a[j]; a[j] = t`) - the swap
    this replaced;
  * a nearest-centre scan (a `minDist`/`Infinity` accumulator beside a distance
    expression) - `indexAt`, spelled locally.

A Fisher-Yates shuffle uses the second idiom legitimately
(`DesktopContextMenu.qml`'s random wallpaper carousel), which is exactly why the
scope is drag files rather than every file: the carve-out is the data, not an
allowlist that has to be maintained.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULES = ROOT / "modules"
LAYOUT_OPS = "layout_ops.js"

# The four sites the module was extracted from. They are named here so the
# sweep cannot go quiet: a rename, a move or a lost `DragHandler` would
# otherwise empty the scope and report a clean tree.
EXPECTED_SITES = {
    "common/widgets/LayoutSection.qml",
    "common/widgets/DragApps.qml",
    "imi/bar/DocktoPanel.qml",
    "imi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml",
}

SPLICE_OUT = re.compile(r"\.splice\s*\(\s*[^,()]+,\s*1\s*\)")
SPLICE_IN = re.compile(r"\.splice\s*\(\s*[^,()]+,\s*0\s*,")
# `list[i] = list[j]` - an element written from another element of the same
# sequence, which no reorder needs and every swap has.
ELEMENT_SWAP = re.compile(
    r"(?P<target>[A-Za-z_$][\w.$]*)\s*\[[^\]]+\]\s*=\s*(?P=target)\s*\[")
DISTANCE_SCAN = re.compile(r"\bInfinity\b")
DISTANCE_MATH = re.compile(r"Math\.(sqrt|abs)\s*\(|\bdx\s*\*\s*dx\b")


def strip_comments(lines):
    """Line comments only. A reorder written inside a block comment is not one,
    and this file's own prose must not read as a violation."""
    out = []
    in_block = False
    for line in lines:
        text = line
        if in_block:
            end = text.find("*/")
            if end == -1:
                out.append("")
                continue
            text = text[end + 2:]
            in_block = False
        start = text.find("/*")
        if start != -1:
            in_block = "*/" not in text[start:]
            text = text[:start] + ("" if in_block else text[text.find("*/") + 2:])
        comment = text.find("//")
        if comment != -1:
            text = text[:comment]
        out.append(text)
    return out


def violations_in(lines):
    """Every local reorder idiom in one file, as (line number, what)."""
    code = strip_comments(lines)
    found = []

    for number, line in enumerate(code, 1):
        if SPLICE_OUT.search(line):
            # The pair may share a line or sit a couple apart, with the removed
            # item stored in between.
            window = " ".join(code[number - 1:number + 3])
            if SPLICE_IN.search(window):
                found.append((number, "a splice-out/splice-in pair is layout_ops.move"))
        if ELEMENT_SWAP.search(line):
            found.append((number, "an indexed element exchange is the swap layout_ops.move replaced"))

    for number, line in enumerate(code, 1):
        if DISTANCE_SCAN.search(line):
            # Generous, because the accumulator is declared before the loop and
            # the distance is computed inside it - LayoutSection had ten lines
            # between the two and a tighter window missed it by one.
            window = " ".join(code[number - 1:number + 14])
            if DISTANCE_MATH.search(window):
                found.append((number, "a nearest-centre scan is layout_ops.indexAt"))

    return found


FIXTURES = {
    "a splice-out/splice-in pair is layout_ops.move": """
        DragHandler {
            onActiveChanged: {
                let list = root.layout.slice()
                const item = list.splice(index, 1)[0]
                list.splice(newIndex, 0, item)
            }
        }
    """,
    "an indexed element exchange is the swap layout_ops.move replaced": """
        DragHandler {
            function swapSlots(from, to) {
                let tmp = arr[from]; arr[from] = arr[to]; arr[to] = tmp
            }
        }
    """,
    "a nearest-centre scan is layout_ops.indexAt": """
        DragHandler {
            function findNewIndex(dragX, dragY) {
                let minDist = Infinity
                for (let i = 0; i < count; i++) {
                    const dx = dragX - c.x
                    const dy = dragY - c.y
                    const dist = Math.sqrt(dx * dx + dy * dy)
                    if (dist < minDist) minDist = dist
                }
            }
        }
    """,
}

CLEAN_FIXTURE = """
    DragHandler {
        onActiveChanged: {
            // A move, not an exchange: dist, Infinity and splice all appear in
            // this comment and none of them is code.
            root.onUpdate(LayoutOps.move(root.layout, index, newIndex))
            root.onUpdate(LayoutOps.remove(root.layout, index))
        }
    }
"""


def self_check():
    """The detectors are proven against fixtures rather than against the tree,
    so a pattern that stopped matching cannot pass as a clean sweep."""
    broken = []
    for expected, source in FIXTURES.items():
        reasons = {reason for _, reason in violations_in(source.splitlines())}
        if expected not in reasons:
            broken.append(f"missed: {expected}")
    if violations_in(CLEAN_FIXTURE.splitlines()):
        broken.append("flagged the adopted spelling")
    return broken


def main() -> int:
    broken = self_check()
    if broken:
        print("Reorder-arithmetic lint FAILED its own self-check: "
              f"{broken}. The sweep below cannot be trusted.", file=sys.stderr)
        return 1

    scoped = []
    for path in sorted(MODULES.rglob("*.qml")):
        lines = path.read_text(encoding="utf-8").splitlines()
        if any("DragHandler" in line for line in lines):
            scoped.append((path, lines))

    found = {str(path.relative_to(MODULES)) for path, _ in scoped}
    missing = EXPECTED_SITES - found
    if missing:
        print("Reorder-arithmetic lint FAILED: the sweep no longer reaches "
              f"{sorted(missing)} - either those files stopped declaring a "
              "DragHandler or they moved, and the sweep would report a clean "
              "tree whatever they contain.", file=sys.stderr)
        return 1

    failed = False
    for path, lines in scoped:
        rel = path.relative_to(MODULES)
        for number, reason in violations_in(lines):
            failed = True
            print(f"Reorder-arithmetic lint FAILED: {rel}:{number}: {reason}. "
                  f"Reorder through modules/common/functions/{LAYOUT_OPS} so "
                  "every surface answers the same way.", file=sys.stderr)

    for site in sorted(EXPECTED_SITES):
        source = (MODULES / site).read_text(encoding="utf-8")
        if LAYOUT_OPS not in source or "LayoutOps." not in source:
            failed = True
            print(f"Reorder-arithmetic lint FAILED: {site} no longer reaches "
                  f"{LAYOUT_OPS}. A surface that stops sharing the arithmetic "
                  "is a surface that can disagree with the other three again.",
                  file=sys.stderr)

    if failed:
        return 1

    print(f"Reorder-arithmetic lint passed ({len(scoped)} QML files declaring "
          f"a DragHandler, {len(EXPECTED_SITES)} of them reordering through "
          f"{LAYOUT_OPS})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
