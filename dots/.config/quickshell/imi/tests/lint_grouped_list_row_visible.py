#!/usr/bin/env python3
"""A GroupedList row that comes and goes declares `rowVisible`, never `visible`.

GroupedList draws one tinted plate per declared row and decides which plates
exist from `item.rowVisible ?? true` (GroupedList.qml's `drawnIndices`). A row
hidden with `visible: false` therefore keeps its plate: a row-height band of
the group's background with nothing in it. The mechanism and the reason the
plate cannot simply mirror the row's `visible` (effective visibility latches -
the row is a descendant of the plate) are documented at the top of
GroupedList.qml and pinned by tst_grouped_list.qml; this is the half that
names the call site.

The rule was written into GroupedList.qml's header and AGENT.md after
b949bf24a ("fix(widgets): a GroupedList row that is not drawn takes no room"),
and this lint's first run still found thirteen `visible:`-gated rows across
five files - the Clight settings section alone kept three empty plates
whenever the daemon was down. A rule stated twice in prose and still broken
thirteen times becomes a failing check.

Scope: only a row's OWN `visible:` binding - the top level of a component
declared directly under `GroupedList {`. The GroupedList's own `visible:` is
fine (it hides the whole surface, plates included), and anything nested
deeper than the row's top level is the row's internal business.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

ROW_OPEN = re.compile(r"\s*[A-Z]\w*\s*\{\s*$")
VISIBLE_BINDING = re.compile(r"\s*visible\s*:")
GROUPED_LIST_OPEN = re.compile(r"\bGroupedList\s*\{")


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return "\n".join(line.split("//")[0] for line in text.split("\n"))


def visible_rows(text: str):
    """Yield (line_number, line) for a `visible:` bound at a row's top level."""
    lines = strip_comments(text).split("\n")
    hits = []
    for start, opener in enumerate(lines):
        if not GROUPED_LIST_OPEN.search(opener):
            continue
        depth = opener.count("{") - opener.count("}")
        row_body_depth = None  # depth while inside a direct row's own body
        j = start + 1
        while j < len(lines) and depth > 0:
            line = lines[j]
            if depth == 1 and ROW_OPEN.match(line):
                row_body_depth = 2
            elif row_body_depth is not None and depth < row_body_depth:
                row_body_depth = None
            if row_body_depth is not None and depth == row_body_depth \
                    and VISIBLE_BINDING.match(line):
                hits.append((j + 1, line.strip()))
            depth += line.count("{") - line.count("}")
            j += 1
    return hits


def self_check():
    offending = """
GroupedList {
    ConfigSwitch {
        visible: Something.available
        text: "row"
    }
}
"""
    clean_row_visible = """
GroupedList {
    ConfigSwitch {
        property bool rowVisible: Something.available
        text: "row"
    }
}
"""
    clean_own_visible = """
GroupedList {
    visible: Something.available
    ConfigSwitch {
        text: "row"
    }
}
"""
    clean_nested = """
GroupedList {
    ConfigRow {
        ConfigSwitch {
            visible: Something.available
        }
    }
}
"""
    problems = []
    if len(visible_rows(offending)) != 1:
        problems.append("detector missed a row-level `visible:` in its own fixture")
    if visible_rows(clean_row_visible):
        problems.append("detector flags `rowVisible`, which is the sanctioned spelling")
    if visible_rows(clean_own_visible):
        problems.append("detector flags the GroupedList's own `visible:`")
    if visible_rows(clean_nested):
        problems.append("detector flags a `visible:` nested below the row's top level")
    return problems


def main() -> int:
    failures = self_check()
    scanned_lists = 0
    for path in sorted((ROOT / "modules").rglob("*.qml")):
        text = path.read_text(encoding="utf-8")
        if "GroupedList" not in text:
            continue
        scanned_lists += 1
        for line_number, line in visible_rows(text):
            failures.append(
                f"{path.relative_to(ROOT)}:{line_number}: a GroupedList row binds "
                f"`visible:` ({line}) - declare `property bool rowVisible:` instead, "
                f"or the hidden row keeps an empty plate (see GroupedList.qml)")
    if scanned_lists < 5:
        failures.append(
            f"only {scanned_lists} files with GroupedList were scanned - the sweep "
            f"is looking at the wrong tree")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"GroupedList row-visibility lint passed over {scanned_lists} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
