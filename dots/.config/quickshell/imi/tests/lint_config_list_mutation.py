#!/usr/bin/env python3
"""Config list properties must be reassigned, never mutated in place.

`Config.options.<...>` list properties are QML `list<var>`s, and a QML list
property emits its change signal on *assignment*. `push`, `splice`, `pop`,
`shift`, `unshift`, `sort` and `reverse` change the array the property already
holds and notify nothing at all, so every binding downstream keeps rendering
the previous value until something unrelated forces a re-evaluation.

That failure is unusually hard to read from the symptoms, because the config
that gets written to disk is correct - only the live view is stale. The Android
quick toggles looked "drunk" for exactly this reason: reordering left each
delegate showing the outgoing toggle's icon, name and action, and a shell
restart "fixed" it because that re-reads the config from disk. Tray pinning had
the same bug, visible as an asymmetry: `unpin` reassigned, `pin` pushed.

Build a new array and assign it back instead:

    Config.options.tray.pinnedItems = pins.concat([itemId])          # good
    Config.options.tray.pinnedItems.push(itemId)                     # broken

Mutating a *local* array before assigning it is fine and is not flagged - the
pattern this catches is a mutating call applied directly to a
`Config.options...` expression.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

MUTATORS = ("push", "splice", "pop", "shift", "unshift", "sort", "reverse")

# Config.options.a.b.c.<mutator>(   — the mutator applied straight to the
# property, with no intervening local binding.
PATTERN = re.compile(
    r"\bConfig\.options(?:\.[A-Za-z_][A-Za-z0-9_]*)+\.(" + "|".join(MUTATORS) + r")\s*\(")


def main() -> int:
    failures = []
    for path in sorted(ROOT.rglob("*.qml")):
        if "/tests/" in str(path):
            continue
        for lineno, line in enumerate(path.read_text().splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            match = PATTERN.search(line)
            if match:
                failures.append(
                    f"{path.relative_to(ROOT)}:{lineno}: "
                    f"`.{match.group(1)}()` on a Config list property does not notify; "
                    f"build a new array and assign it back\n    {line.strip()}")

    if failures:
        print("Config list properties mutated in place:\n")
        print("\n".join(failures))
        return 1
    print("No in-place Config list mutations found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
