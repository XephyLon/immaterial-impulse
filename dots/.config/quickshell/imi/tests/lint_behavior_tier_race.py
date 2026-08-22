#!/usr/bin/env python3
"""Fail if a Behavior picks its tier from the same state that imperatively starts it.

A `NumberAnimation` inside a `Behavior` latches its `duration` and `easing` when
it STARTS. When the animated property is written imperatively from a handler for
some flag, and the animation's parameters are bindings on that same flag, nothing
orders the binding update before the handler. The animation can begin still
holding the other branch - so a close runs the entrance curve.

It is invisible in every way that usually catches things. The source reads
correctly, both tiers are catalogued, no warning is logged, the QML suite never
builds the component, and a frame comparison of the settled states passes because
the animation does arrive at the right place. Only the SHAPE of the travel is
wrong, and only a frame-by-frame capture shows it.

Measured on `WallpaperSelector`'s close: 659px of travel whose per-frame share
went 32.2 16.1 10.8 8.0 6.8, against 32.6 14.5 10.4 8.1 6.5 predicted by the
entrance curve and 1.3 3.2 4.4 5.3 5.9 by the exit one. The panel decelerated
out - a third of the way gone in a single frame, then coasting.

The fix is to hold the tier as plain state and assign it before the write, which
IS ordered: a QML property write propagates to dependent bindings synchronously.
`DesktopContextMenu.qml` already did it that way.

Scoped to the shape that actually bites. A Behavior whose parameters branch on
state is fine when the animated property is a declarative binding on that same
state - both re-evaluate in one pass and there is no handler to race. What this
forbids is the combination: a ternary on X in the Behavior, and an imperative
write to the animated property from `onXChanged`.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMENT = re.compile(r"//[^\n]*")


def uncommented(text):
    return COMMENT.sub("", text)


def _block(text, open_brace):
    depth, i = 0, open_brace
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(text)


def offenders():
    found = []
    for path in sorted(ROOT.rglob("*.qml")):
        if ".git" in path.parts:
            continue
        text = uncommented(path.read_text(errors="ignore"))
        for match in re.finditer(r"Behavior on (\w+)\s*\{", text):
            prop = match.group(1)
            body = text[match.end():_block(text, match.end() - 1)]
            # Which flags does this Behavior's tier branch on?
            flags = set()
            for line in body.splitlines():
                if not re.search(r"\b(duration|easing\.\w+)\s*:", line):
                    continue
                for name in re.findall(r"([\w.]+)\s*$", line.split("?")[0]):
                    if name.endswith((".duration", ".type", ".bezierCurve")):
                        continue
                    flags.add(name.split(".")[-1])
            for flag in flags:
                # ...and is the animated property written from that flag's own
                # change handler? EVERY such handler, not the first: a file may
                # answer the same signal in more than one place, and the first
                # draft of this check looked only at `re.search`'s single hit -
                # which in the file it was written for was the wrong one of two,
                # so it passed on the very bug it names.
                pattern = r"function on%s%sChanged\s*\([^)]*\)\s*\{" % (
                    flag[0].upper(), flag[1:])
                for handler in re.finditer(pattern, text):
                    hbody = text[handler.end():_block(text, handler.end() - 1)]
                    if re.search(r"[\w.]*\.?%s\s*=" % re.escape(prop), hbody):
                        found.append((path.relative_to(ROOT).as_posix(), prop, flag))
                        break
    return found


class BehaviorTierRace(unittest.TestCase):
    def test_no_behavior_takes_its_tier_from_the_flag_that_starts_it(self):
        bad = offenders()
        self.assertEqual(
            [], bad,
            "these pick a Behavior's duration/easing from the same flag whose "
            "change handler writes the animated property, so the animation can "
            "start holding the wrong tier: "
            + ", ".join(f"{f}: Behavior on {p} branches on {c}" for f, p, c in bad))


if __name__ == "__main__":
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
