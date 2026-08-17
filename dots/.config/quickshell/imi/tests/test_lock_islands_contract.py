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


if __name__ == "__main__":
    raise SystemExit(run(globals()))
