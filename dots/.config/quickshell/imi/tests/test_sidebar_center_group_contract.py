#!/usr/bin/env python3
"""The right sidebar's fill-height section paints nothing when it has no room.

`CenterWidgetGroup` is the column's only `Layout.fillHeight: true` item and
declares no minimum, so when the fixed-height sections around it (banner,
toggles, sliders, media player, the bottom group expanded) fill the column,
the layout hands it 0 - and the notification list inside, inset by its
margins, ends up with NEGATIVE height. Only the list's scroll view clipped;
the empty state's bell and "Nothing" and the "0 notifications" status pill
kept painting around a rectangle with no area, over the media player and
the bottom group's tabs (user-reported, 2026-08-26).

Two rules, read at the group and the list:

- the group clips, so nothing inside can ever paint outside its area;
- the list is hidden below a height the list itself names
  (`minimumUsefulHeight`: its status row, the gap, one line above), so a
  sliver of room never shows a cut-off pill either.

Every sweep asserts it FOUND what it swept for.
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
GROUP = ROOT / "modules/imi/sidebarRight/CenterWidgetGroup.qml"
LIST = ROOT / "modules/imi/sidebarRight/notifications/NotificationList.qml"
COLUMN = ROOT / "modules/imi/sidebarRight/SidebarRightContent.qml"


def code(path: Path) -> str:
    assert path.exists(), f"{path} is gone - the sweep has nothing to look at"
    text = path.read_text()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def test_the_group_is_the_columns_fill_height_section():
    text = code(COLUMN)
    block = re.search(r"CenterWidgetGroup\s*\{(.*?)\n\s{12}\}", text, flags=re.S)
    assert block, "SidebarRightContent no longer places a CenterWidgetGroup"
    assert re.search(r"Layout\.fillHeight\s*:\s*true", block.group(1)), \
        ("CenterWidgetGroup is no longer the fill-height section - this rule "
         "is about the one item the layout can hand nothing to")


def test_the_group_clips_and_hides_its_list_below_a_useful_height():
    text = code(GROUP)
    assert re.search(r"^\s{4}clip\s*:\s*true", text, flags=re.M), \
        ("CenterWidgetGroup does not clip - a list inset into a zero-height "
         "rectangle paints its unclipped pieces over the neighbours")
    gate = re.search(r"NotificationList\s*\{(.*?)\n\s{4}\}", text, flags=re.S)
    assert gate, "CenterWidgetGroup no longer holds a NotificationList"
    visible = re.search(r"visible\s*:(.*)", gate.group(1))
    assert visible, "the NotificationList has no `visible:` gate of its own"
    assert "minimumUsefulHeight" in visible.group(1) and "height" in visible.group(1), \
        (f"the list's gate `{visible.group(1).strip()}` does not compare the "
         "group's height against the list's minimumUsefulHeight")


def test_the_list_names_its_own_minimum():
    text = code(LIST)
    decl = re.search(r"readonly\s+property\s+real\s+minimumUsefulHeight\s*:(.*?)\n\n", text, flags=re.S)
    assert decl, "NotificationList declares no minimumUsefulHeight"
    assert "statusRow.implicitHeight" in decl.group(1), \
        ("minimumUsefulHeight does not start from the status row's own height "
         "- the row is the piece that was painting over the media player")


if __name__ == "__main__":
    raise SystemExit(run(globals()))
