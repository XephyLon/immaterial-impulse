#!/usr/bin/env python3
"""The todo lists ride StyledListView's own transitions, on an identity-stable model.

docs/p3drovfx-animation-research-2026-08-16.md §4.7: we own a StyledListView
with the full positioner-transition vocabulary and use it in fewer places than
the sibling fork. The todo TaskList was the clearest case - it drew through
StyledListView and switched the transitions OFF (`animateAppearance: false`,
inherited from the fork ancestry, not a decision made here: the flag predates
this repo's history).

Turning the flag back on is half the fix, and the half a reviewer cannot see is
the model: Quickshell's ScriptModel diffs `values` by strict equality
(scriptmodel.cpp `a.strictlyEquals(b)` with no `objectProp` set), so
TodoWidget's old per-update wrapper - `.map(Object.assign({}, item,
{originalIndex: i}))` - handed it a list of brand-new objects on every change.
Every update then diffed as remove-all + add-all: with transitions off that was
silent delegate churn, with them on it would fly the entire list out and back
in when one task is marked done. The wrapper is gone; the filters pass
`Todo.list`'s own objects through (Todo mutates items in place and reassigns
the array, so identity survives a markDone/markUnfinished/delete), and the
delegate resolves an item's index at click time with `Todo.list.indexOf`,
which also cannot go stale across deletes the way a stored index could.

`animateMovement` stays at its default (off) deliberately: the diff emits
inserts and removes, never model moves, so the move/displaced slots have
nothing to fire on.

Why a source contract: qmltestrunner cannot construct Quickshell types, so
neither ScriptModel's diff nor a ListView transition is reachable from the QML
suite; the identity chain is exactly the part that reads correctly while
broken.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contract_runner import run  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
TASK_LIST = ROOT / "modules/imi/sidebarRight/todo/TaskList.qml"
TODO_WIDGET = ROOT / "modules/imi/sidebarRight/todo/TodoWidget.qml"


def code(path: Path) -> str:
    assert path.exists(), f"{path} is gone"
    text = path.read_text()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def test_the_task_list_keeps_the_views_transitions_armed():
    text = code(TASK_LIST)
    assert "StyledListView" in text, "TaskList no longer draws through StyledListView"
    assert not re.search(r"animateAppearance:\s*false", text), \
        "TaskList switched the view's add/remove transitions back off"
    assert re.search(r"ScriptModel\s*\{", text), \
        "TaskList no longer models through ScriptModel - what diffs the list now?"


def test_the_model_is_fed_identity_stable_values():
    widget = code(TODO_WIDGET)
    filters = re.findall(r"taskList:\s*Todo\.list\.filter", widget)
    assert len(filters) == 2, \
        (f"expected both tabs to pass Todo.list's own objects straight into "
         f"their filter, found {len(filters)} - a per-update wrapper makes "
         "every change diff as remove-all + add-all")
    for path in (TODO_WIDGET, TASK_LIST):
        assert "Object.assign" not in code(path), \
            f"{path.name} wraps model values in fresh objects again"
        assert "originalIndex" not in code(path), \
            f"{path.name} stores an index that goes stale across deletes"


def test_the_delegate_resolves_indices_at_click_time():
    text = code(TASK_LIST)
    calls = re.findall(r"Todo\.list\.indexOf\(", text)
    assert len(calls) == 2, \
        (f"expected the done-toggle and the delete to resolve their index "
         f"with Todo.list.indexOf at click time, found {len(calls)}")


if __name__ == "__main__":
    raise SystemExit(run(globals()))
