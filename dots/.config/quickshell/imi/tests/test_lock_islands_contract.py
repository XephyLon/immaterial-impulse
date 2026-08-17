#!/usr/bin/env python3
"""The lock islands' order: one schema, one resolver, one commit path.

Stage 9b (spec §14, answered "reorder" by the maintainer): three ordered lists
in `Config.options.lock.islands` and a data-driven rewrite of the three
islands in `LockSurface.qml`. What this module pins is the drift that would be
silent:

- the schema's defaults and the resolver's defaults are two spellings of one
  order, so they are pinned equal - a divergence renders existing users a
  different lock screen than the one their (empty) store means;
- every island renders through the resolver, so a version-skewed list cannot
  silently drop an item;
- the reorder commits go through `layout_ops` + `lock_islands` at literal
  config paths, guarded on the mode.

Like the lock preview contract, sweeps here assert they FOUND what they swept.
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "modules/common/Config.qml"
MODULE = ROOT / "modules/common/functions/lock_islands.js"
LOCK_SURFACE = ROOT / "modules/imi/lock/LockSurface.qml"


def read(path: Path) -> str:
    assert path.exists(), f"{path} is gone - the sweep has nothing to look at"
    text = path.read_text()
    assert text.strip(), f"{path} is empty"
    return text


def code(path: Path) -> str:
    text = re.sub(r"/\*.*?\*/", "", read(path), flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def module_default(name: str):
    match = re.search(rf"var {name}_DEFAULT = \[(.*?)\];", code(MODULE), re.S)
    assert match, f"lock_islands.js no longer declares {name}_DEFAULT"
    return re.findall(r'"(\w+)"', match.group(1))


def test_the_schema_and_the_resolver_agree_on_the_default_order():
    # Config.qml cannot import the module (a JsonAdapter default is safest as
    # a literal), so the two spellings of the hand-placed order are pinned
    # against each other here instead of trusted to stay equal.
    config = code(CONFIG)
    islands = re.search(
        r"property JsonObject islands: JsonObject \{(.*?)\n            \}",
        config, re.S)
    assert islands, "Config.qml declares no lock.islands schema"
    body = islands.group(1)
    for name in ("main", "left", "right"):
        declared = re.search(
            rf"property list<string> {name}:\s*\[(.*?)\]", body, re.S)
        assert declared, f"lock.islands.{name} is not declared"
        stored = re.findall(r'"(\w+)"', declared.group(1))
        expected = module_default(name.upper())
        assert stored == expected, \
            (f"lock.islands.{name} defaults to {stored} while the resolver's "
             f"default is {expected} - two spellings of one order have split")


def all_default_ids():
    ids = []
    for name in ("MAIN", "LEFT", "RIGHT"):
        ids.extend(module_default(name))
    assert len(ids) >= 10, f"the module's defaults shrank to {ids}"
    return ids


def test_the_islands_render_through_the_one_resolver():
    # Each island's Repeater models the resolver's answer, never the stored
    # list directly: the resolver is where the version-skew rules live (a
    # missing known id renders at its default position; an unknown one is
    # skipped without being destroyed), and a Repeater over the raw list
    # would silently drop both rules.
    raw = read(LOCK_SURFACE)
    assert "lock_islands.js" in raw, \
        "LockSurface no longer imports the islands module"
    text = code(LOCK_SURFACE)
    for name, default in (("mainOrder", "MAIN_DEFAULT"),
                          ("leftOrder", "LEFT_DEFAULT"),
                          ("rightOrder", "RIGHT_DEFAULT")):
        assert re.search(
            rf"property var {name}:\s*LockIslands\.orderedItems\(\s*\n?\s*"
            rf"Config\.options\.lock\.islands\.\w+,\s*LockIslands\.{default}\)",
            text), \
            f"{name} is not the resolver over the stored list and its defaults"
    models = re.findall(r"model:\s*root\.(main|left|right)Order", text)
    assert sorted(models) == ["left", "main", "right"], \
        f"expected the three islands to model the three orders, found {models}"


def test_every_default_id_has_a_component_and_its_layout_metadata():
    # A default id with no component entry renders as an empty slot - the
    # Loader resolves null and draws nothing, silently, which is the exact
    # disappearance the resolver exists to prevent arriving from the other
    # side. Same for the layout metadata: a missing entry is not an error,
    # it is a margin of 0 that reads as a design choice.
    text = code(LOCK_SURFACE)
    components = re.search(r"islandComponents:\s*\(\{(.*?)\}\)", text, re.S)
    assert components, "LockSurface declares no islandComponents map"
    meta = re.search(r"islandItemMeta:\s*\(\{(.*?)\n    \}\)", text, re.S)
    assert meta, "LockSurface declares no islandItemMeta map"
    for item in all_default_ids():
        assert re.search(rf"\b{item}:", components.group(1)), \
            f"islandComponents has no entry for {item}"
        assert re.search(rf"\b{item}:", meta.group(1)), \
            f"islandItemMeta has no entry for {item}"


def test_the_password_field_is_reachable_and_pinned_by_the_module():
    # The field lives inside a delegate component now, so forceFieldFocus
    # reaches it through the property the component publishes - and the
    # module, not the surface, is what says it cannot be reordered.
    text = code(LOCK_SURFACE)
    assert re.search(r"property Item passwordField", text), \
        "the surface no longer publishes the password field"
    assert re.search(r"root\.passwordField\?\.forceActiveFocus\(\)", text), \
        "forceFieldFocus no longer reaches the field through the property"
    module = code(MODULE)
    assert re.search(r'island === "main" && id === "password"', module), \
        "the module no longer pins the password field as unmovable"


CONTROLLER = ROOT / "modules/imi/lock/LockIslandReorder.qml"
EDIT_ITEM = ROOT / "modules/imi/lock/LockIslandEditItem.qml"
CANVAS = ROOT / "modules/common/widgets/widgetCanvas/WidgetCanvas.qml"
GLOBAL_STATES = ROOT / "GlobalStates.qml"


def test_the_reorder_commits_through_the_shared_arithmetic_at_literal_paths():
    # No fifth copy of the reorder (spec §10.2): the gesture is ReorderDragArea,
    # the list arithmetic is layout_ops, the write-back merge is the module's
    # storedOrder, and the three stored lists are literal paths - an allowlist
    # reachable through a computed key is not an allowlist, which is the scope
    # lint's own rule about these files.
    text = code(CONTROLLER)
    # `dropTarget` itself lives inside ReorderDragArea - the controller's half
    # of that seam is the buckets provider the gesture calls.
    for required in ("LayoutOps.move(", "LayoutOps.moveTargetForInsertion(",
                     "LockIslands.storedOrder(", "function dropBuckets"):
        assert required in text, f"the controller no longer uses {required}"
    item = code(EDIT_ITEM)
    assert "ReorderDragArea" in item and "bucketsProvider" in item, \
        ("the edit item's gesture must be the shared ReorderDragArea over the "
         "controller's buckets - anything else is the fifth copy")
    for island in ("main", "left", "right"):
        assert re.search(rf"Config\.options\.lock\.islands\.{island}\s*=", text), \
            f"the controller does not write lock.islands.{island} at its literal path"
    commit = re.search(r"function commitReorder\([^)]*\)\s*\{(.*?)\n    \}", text, re.S)
    assert commit, "the controller no longer declares commitReorder"
    assert re.search(r"if \(!GlobalStates\.editMode", commit.group(1)), \
        ("the commit must be guarded on the mode - a drag can outlive it, and "
         "an end the user meant as stop must not store an order")
    assert "DragHandler" not in text, \
        ("the controller grew a DragHandler - the gesture is ReorderDragArea, "
         "and a second handler is the fifth copy §10.2 forbids")


def test_the_overlay_arms_only_for_the_preview_and_movable_items():
    text = code(LOCK_SURFACE)
    overlay = re.search(r"sourceComponent:\s*LockIslandEditItem", text)
    assert overlay, "LockSurface no longer loads the island edit overlay"
    loader = re.search(
        r"active:\s*!root\.interactive\s*&&\s*GlobalStates\.editMode\s*\n?\s*"
        r"&&\s*LockIslands\.reorderable\(", text)
    assert loader, \
        ("the overlay must arm only in the preview, in the mode, and never on "
         "the password field - the module's reorderable() is what says so")


def test_the_ladder_sees_a_lock_island_drag():
    # Escape mid-drag must cancel the gesture, not exit the mode - the same
    # composition the bar drag earned in stage 8, through a flag of its own
    # because the two gestures live on different surfaces and are cleared by
    # different teardowns.
    states = code(GLOBAL_STATES)
    assert re.search(r"property bool editLockDragActive:\s*false", states), \
        "GlobalStates no longer declares the lock drag flag"
    handler = re.search(r"onEditModeChanged:\s*\{(.*?)\n    \}", states, re.S)
    assert handler and "editLockDragActive = false" in handler.group(1), \
        "leaving the mode must clear the lock drag flag"
    canvas = code(CANVAS)
    ladder = re.search(r"gestureInFlight:(.*?),\s*\n\s*selectionCount", canvas, re.S)
    assert ladder and "editLockDragActive" in ladder.group(0), \
        "the canvas ladder does not see a lock island drag"
    # Seeing the drag is only half the wiring: the cancel branch must also
    # EMIT the return path for it. With only the bar's flag in the emit gate,
    # Escape mid-lock-drag resolves to cancelGesture, is consumed doing
    # nothing, and the eventual release COMMITS the order the user tried to
    # abandon - the commit's own guard checks the mode, which is still on.
    cancel = re.search(r'else if \(action === "cancelGesture"\)\s*\{(.*?)\n\s*\}',
                       canvas, re.S)
    assert cancel, "the canvas no longer has a cancelGesture branch"
    assert "editLockDragActive" in cancel.group(1), \
        ("the cancel branch never reaches a lock island drag - Escape is "
         "swallowed and the release commits")
    item = code(EDIT_ITEM)
    assert "onEditReorderCancel" in item, \
        "the edit item does not answer the ladder's cancel"


if __name__ == "__main__":
    raise SystemExit(run(globals()))
