#!/usr/bin/env python3
"""Fail if a handler writes an animated property and then defers a second write to it.

The idiom looks like "put it where it comes from, then send it home":

    function slideIn() {
        content.y = -content.height;          // the start
        Qt.callLater(() => { content.y = 0 }); // the end
    }

and it does nothing at all. `y` carries a `Behavior`, so the first write does not
set a value - it STARTS an animation toward it. `Qt.callLater` runs in the same
turn of the event loop, before a single frame is drawn, so that animation has
advanced ~0ms when the second write retargets it. Qt retargets from where the
property actually is, which is where it already was, and the result is an
animation from A to A: no motion, no warning, and QML that reads exactly like an
entrance.

Measured, that is what the wallpaper selector's entrance was for the whole life
of the feature. On a 60fps capture in a nested compositor, with a control pair of
frames differing by 0.0000, the panel's drawn bottom edge went from off screen to
99.6% of its final position in ONE frame - 690px in 17ms - while the exit, whose
write has no deferred partner, animated correctly over its whole tier. So the
surface popped in and slid out, and the asymmetry read as a broken exit rather
than as a missing entrance.

The repair is to make the start state DECLARED rather than written -
`property real openProgress: 0`, or `scale: 0.85` as `DesktopMenu` and
`EditWidgetMenu` already write it - and to write only the destination. A
declared initial value is not a write, so no Behavior swallows it.

Scoped to the combination that cannot be anything else. Two writes to one
property in a body are ordinarily an if/else, which is fine; a write PLUS a
deferred write to the same property is a start value and a destination, and the
deferral is there precisely to make the first one visible, which is the thing it
prevents.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMENT = re.compile(r"//[^\n]*")
BEHAVIOR = re.compile(r"Behavior on (\w+)\s*\{")
BODY_START = re.compile(
    r"(?:function\s+\w+\s*\([^)]*\)\s*\{|\bon[A-Z]\w*\s*:\s*\{)")
CALL_LATER = re.compile(r"Qt\.callLater\s*\(")


def uncommented(text):
    return COMMENT.sub("", text)


def block(text, open_brace):
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


def writes(body, prop):
    """Assignments to `prop`, as `x.prop =` or a bare `prop =`, never `==`."""
    return list(re.finditer(r"(?<![\w.])(?:[\w.]+\.)?%s\s*=(?!=)" % re.escape(prop), body))


def scan(text):
    """(prop, line-offset) for each body that writes prop AND defers a write to it."""
    text = uncommented(text)
    animated = set(BEHAVIOR.findall(text))
    if not animated:
        return []
    found = []
    for start in BODY_START.finditer(text):
        brace = text.index("{", start.end() - 1)
        body = text[brace:block(text, brace) + 1]
        for prop in animated:
            hits = writes(body, prop)
            if len(hits) < 2:
                continue
            # ...and at least one of them is inside a deferred closure, which is
            # what makes the earlier one a start value rather than a branch.
            deferred = False
            for later in CALL_LATER.finditer(body):
                tail = body[later.start():]
                if writes(tail, prop):
                    deferred = True
                    break
            if deferred:
                found.append((prop, start.start()))
    return found


def offenders():
    bad = []
    for path in sorted(ROOT.rglob("*.qml")):
        if ".git" in path.parts:
            continue
        for prop, offset in scan(path.read_text(errors="ignore")):
            line = path.read_text(errors="ignore").count("\n", 0, offset) + 1
            bad.append(f"{path.relative_to(ROOT).as_posix()}:{line}: `{prop}`")
    return bad


FIXTURE_BAD = """
Item {
    Behavior on y { NumberAnimation {} }
    function slideIn() {
        content.y = -content.height;
        Qt.callLater(() => { content.y = 0; });
    }
}
"""

# An if/else writing one animated property twice is not this - only one branch
# runs, and neither is a start value the other cancels.
FIXTURE_BRANCH = """
Item {
    Behavior on y { NumberAnimation {} }
    function place(up) {
        if (up) content.y = 0;
        else content.y = 100;
    }
}
"""

# A deferred write on its own is the ordinary "measure next turn" deferral.
FIXTURE_DEFERRED_ONLY = """
Item {
    Behavior on y { NumberAnimation {} }
    function place() {
        Qt.callLater(() => { content.y = 0; });
    }
}
"""


class AnimatedStartWrite(unittest.TestCase):
    def test_the_detector_finds_the_idiom_and_leaves_its_neighbours(self):
        self.assertEqual(1, len(scan(FIXTURE_BAD)),
                         "the detector no longer recognises the idiom it exists for")
        self.assertEqual([], scan(FIXTURE_BRANCH),
                         "an if/else over one animated property is not a start write")
        self.assertEqual([], scan(FIXTURE_DEFERRED_ONLY),
                         "a lone deferred write is an ordinary next-turn deferral")

    def test_no_animated_property_is_written_to_its_own_start_value(self):
        bad = offenders()
        self.assertEqual(
            [], bad,
            "these write an animated property and then defer a second write to "
            "it, so the first write is swallowed by the retarget and the "
            "animation runs from its destination to its destination: "
            + ", ".join(bad)
            + ". Declare the start value instead of writing it.")


if __name__ == "__main__":
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
