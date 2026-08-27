#!/usr/bin/env python3
"""A MaterialSymbol used as a Control's contentItem says how it is aligned.

A Control (RippleButton is one) sizes its `contentItem` to the padded rect
and positions it itself; anchors set on the contentItem are ignored. A
`MaterialSymbol` is a Text, and a Text with no alignment draws its glyph at
the top-left of whatever rect it is given - so `anchors.centerIn: parent`
on a contentItem glyph is decoration, and the icon sits up-left of centre.
That is the presets "save" button the maintainer photographed (2026-08-27),
and seven more buttons had the same spelling, one of them hand-nudged with
`anchors.horizontalCenterOffset: -2` to hide it.

`IconToolbarButton.qml` is the spelling that is right: both alignments on
the glyph. This lint fails any `contentItem: MaterialSymbol { ... }` block
that lacks either one.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OPENER = re.compile(r"contentItem\s*:\s*MaterialSymbol\s*\{")


def blocks(text):
    for m in OPENER.finditer(text):
        depth, i = 0, m.end() - 1
        while i < len(text):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    yield text[:m.start()].count("\n") + 1, text[m.start():i + 1]
                    break
            i += 1


failures = []
checked = 0
for path in sorted((ROOT / "modules").rglob("*.qml")):
    text = re.sub(r"//[^\n]*", "", path.read_text(errors="replace"))
    for line, block in blocks(text):
        checked += 1
        missing = [a for a in ("horizontalAlignment: Text.AlignHCenter", "verticalAlignment: Text.AlignVCenter") if a not in block]
        if missing:
            failures.append(f"{path.relative_to(ROOT)}:{line}: contentItem MaterialSymbol lacks {', '.join(missing)}")

assert checked, "no contentItem: MaterialSymbol blocks found - the sweep has nothing to look at"
for f in failures:
    print(f"MISALIGNED: {f}")
if failures:
    sys.exit(1)
print(f"Icon glyph alignment lint passed ({checked} contentItem glyphs declare both alignments)")
