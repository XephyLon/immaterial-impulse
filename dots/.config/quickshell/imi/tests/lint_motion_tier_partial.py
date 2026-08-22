#!/usr/bin/env python3
#
# Regression guard: an animation that takes a motion tier's `duration` must
# take an easing with it. Half a tier is silently a generic curve.
#
#   NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
#
# reads as compliant - it names a token, it has no millisecond literal, and
# `docs/M3_GUIDELINES.md` §2's rule about raw durations is satisfied. It leaves
# `easing.type` at Qt's default, which is `Easing.Linear`: the generic curve
# that same section forbids outright. Nothing about the source shows it, no
# warning is logged, and the QML suite never builds these widgets.
#
# This is a check rather than another note because the note already existed and
# the mistake was made anyway, twice in two days, in code someone was actively
# looking at:
#
#   - 2044e1b3b ("fix(bar): give the util button's expand the curve it names")
#     repaired the two size Behaviors in `modules/imi/bar/UtilButton.qml` and
#     left THREE more partial takes in the same file, on the colour and opacity
#     Behaviors a few lines below. They are still there; they are in this
#     check's register.
#   - 8d81d7471 ("fix(editMode): take the motion tiers whole instead of half of
#     one each") found the resize grip's `Behavior on opacity` doing it, and
#     recorded that every grip in the shell had faded linearly since the file
#     was written.
#
# AGENT.md's design-language section states the rule ("Take a motion tier
# whole, because half of one is silently a generic curve"). A rule that has
# been written down and broken twice is a rule that wants a failing check, not
# a third paragraph.
#
# THE REGISTER, and why it is a ratchet rather than a bulk fix.
#
# The tree carries 40 of these across 17 files. They are not fixed here, for
# the reason `docs/M3_GUIDELINES.md` §3 already gives for the whole class:
# "the easing *curve shape* in particular was deliberately left untouched
# during the token migration, since swapping curve shape (unlike reusing a
# matching duration number) is visually perceptible and wasn't verified against
# a running compositor". Forty unverified visual changes in one branch is worse
# than forty known ones in a register.
#
# So EXISTING holds a count per file, and the check fails three ways:
#
#   - a file outside the register has any partial take (new code cannot add
#     one);
#   - a registered file has MORE than its count (an existing offender may not
#     breed);
#   - a registered file has FEWER than its count (fixing one is required to
#     move the number down, so the register cannot rot into a permanent
#     allowlist that nobody rechecks).
#
# What it does NOT fail on, deliberately:
#
#   - An easing that is present but generic (`easing.type: Easing.OutQuad`).
#     That is the separate, already-registered nonconformance in
#     `docs/M3_GUIDELINES.md` §3, and it is a different failure: the author
#     chose a curve, where this check is about a curve nobody chose.
#   - A duration from one tier beside a curve spelled straight out of
#     `Appearance.animationCurves` (SpanTravel, DockIconMotion and about thirty
#     others). Those pair the tier with its OWN curve today, so they are a
#     drift risk rather than a live defect, and folding them in here would
#     triple the register for no bug.
#   - `PauseAnimation`, `SmoothedAnimation` and `SpringAnimation`, which have
#     no easing curve to take.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The animation types that interpolate a value along an easing curve. A
# PauseAnimation has a duration and no curve; a SmoothedAnimation and a
# SpringAnimation have neither.
EASED_ANIMATION = re.compile(
    r"\b(NumberAnimation|ColorAnimation|PropertyAnimation|RotationAnimation)\s*\{")
# `Appearance.animation.<tier>.duration`, with QML's optional chaining allowed
# at every hop the way the rest of the tree writes it.
TIER_DURATION = re.compile(
    r"\bAppearance\s*\??\s*\.\s*animation\s*\??\s*\.\s*(\w+)\s*\??\s*\.\s*duration\b")
# Any easing assignment at all - `easing.type`, `easing.bezierCurve`,
# `easing.overshoot`. Presence is what this check is about; which curve was
# chosen is §3's separate register.
EASING = re.compile(r"\beasing\s*\.\s*\w+\s*:")

# path (repo-relative, POSIX) -> number of partial takes it is allowed to keep.
# May only go DOWN. See the header for why it exists at all.
EXISTING = {
    "modules/imi/overview/NiriOverview.qml": 10,
}


def block_at(text: str, brace_index: int) -> str:
    """The declaration body starting at `brace_index`, brace-matched.

    Read as a whole rather than line by line: every partial take in this tree
    spans several lines, and a line-scoped check would see only the line
    carrying the duration and report a clean tree - the failure mode
    `test_geometry_rects_come_from_the_settled_span_not_the_animating_box`
    already paid for once.
    """
    depth = 0
    for index in range(brace_index, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace_index:index + 1]
    return text[brace_index:]


def partial_takes(text: str):
    """(line, tier) for every eased animation naming a tier and no easing."""
    found = []
    for match in EASED_ANIMATION.finditer(text):
        brace = text.index("{", match.start())
        block = block_at(text, brace)
        duration = TIER_DURATION.search(block)
        if not duration or EASING.search(block):
            continue
        found.append((text.count("\n", 0, match.start()) + 1, duration.group(1)))
    return found


FIXTURE_PARTIAL = """
Item {
    Behavior on opacity {
        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
    }
}
"""

FIXTURE_WHOLE = """
Item {
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on width {
        PauseAnimation { duration: Appearance.animation.elementMove.duration }
    }
    Behavior on height {
        NumberAnimation { duration: 200 }
    }
}
"""


def self_check() -> list:
    """Prove the machinery independently of what the tree happens to contain.

    A source-text check whose only evidence is "it found what is there" agrees
    with itself. These two fixtures are the smallest pair that separates the
    thing being detected from the three things deliberately not detected.
    """
    problems = []
    if len(partial_takes(FIXTURE_PARTIAL)) != 1:
        problems.append("self-check: a duration-only NumberAnimation was not detected")
    if partial_takes(FIXTURE_WHOLE):
        problems.append(
            "self-check: a whole tier, a PauseAnimation or a literal duration "
            "was reported as a partial take")
    return problems


def main() -> int:
    failures = self_check()
    counted = {}
    scanned = 0

    for path in sorted(ROOT.rglob("*.qml")):
        relative = path.relative_to(ROOT).as_posix()
        if relative.startswith("tests/"):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        scanned += 1
        takes = partial_takes(text)
        if takes:
            counted[relative] = takes

    for relative, takes in sorted(counted.items()):
        allowed = EXISTING.get(relative, 0)
        if len(takes) <= allowed:
            continue
        for line, tier in takes[allowed:]:
            failures.append(
                f"{relative}:{line}: takes `{tier}.duration` and leaves its "
                f"curve, so this animation runs on Easing.Linear. Take the "
                f"tier whole - its `numberAnimation`/`colorAnimation` "
                f"Component carries duration, type and curve together, or "
                f"write out `{tier}.type` and `{tier}.bezierCurve` beside the "
                f"duration where `alwaysRunToEnd` would change the behaviour.")

    for relative, allowed in sorted(EXISTING.items()):
        actual = len(counted.get(relative, ()))
        if actual < allowed:
            failures.append(
                f"{relative}: the register allows {allowed} partial takes and "
                f"the file now has {actual}. Lower the number in "
                f"tests/lint_motion_tier_partial.py - the register is a "
                f"ratchet, and one that is not tightened stops being read.")

    if failures:
        print("Motion tier lint failed:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    outstanding = sum(len(takes) for takes in counted.values())
    print(f"Motion tier lint passed ({scanned} QML files, {outstanding} "
          f"registered partial takes in {len(counted)} files still outstanding)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
