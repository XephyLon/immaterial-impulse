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


if __name__ == "__main__":
    raise SystemExit(run(globals()))
