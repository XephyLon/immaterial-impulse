#!/usr/bin/env python3
#
# Regression guard: a wave member's opacity is the wave's channel, and a
# `Behavior on opacity` on the member is a second animation on it.
#
# A component whose root declares `property real appear` is a StaggerWave
# member: the wave assigns `appear = 0` to park it (a snap, deliberately -
# see StaggerWave.park()'s comment) and animates `appear` to 1 to bring it
# in, with the member's opacity riding `appear` - either through the
# member's own fold (RippleButton) or through the binding StaggerEntrance
# installs. A root-level `Behavior on opacity` in the same file intercepts
# every write that binding makes:
#
#  - park()'s snap-to-invisible becomes an on-stage fade-out, so the member
#    is drawn at full strength on the frames the park exists to clear;
#  - the wave's own animation retargets the Behavior every frame, which
#    restarts it every frame (b710ef731's frozen-Behavior shape), so the
#    drawn opacity is pinned near wherever the fade-out left it until
#    `appear` STOPS, and the member lands a whole fade-length after its
#    slot.
#
# That is exactly what the android quick toggles shipped: the tiles' old
# `opacity: 0` + `onCompleted` self-fade was retired in favour of the wave
# (8a0120c2) and the Behavior that had animated it was left behind - so on
# every sidebar open the first-ranked tiles read as "visible at all times,
# then the animation begins", measured on the live shell as appear=0 with
# drawn opacity still 1.000 at the open and 0.147 while appear was at 0.955.
#
# Nested `Behavior on opacity` declarations (a ripple overlay, a scroll
# shadow) animate a child's own opacity, not the member's channel, and stay
# free.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = ROOT / "modules"

# Root-level: the repo indents QML with four spaces, so a property of the
# root object sits at one level and anything nested sits deeper - the same
# assumption lint_disabled_opacity.py rests on.
ROOT_APPEAR = re.compile(r"^ {1,4}property real appear\b")
ROOT_OPACITY_BEHAVIOR = re.compile(r"^ {1,4}Behavior on opacity\b")


def scan(text):
    appear_line = None
    behavior_line = None
    for number, line in enumerate(text.splitlines(), start=1):
        if appear_line is None and ROOT_APPEAR.match(line):
            appear_line = number
        if behavior_line is None and ROOT_OPACITY_BEHAVIOR.match(line):
            behavior_line = number
    if appear_line is not None and behavior_line is not None:
        return behavior_line
    return None


def self_check():
    offender = (
        "GroupButton {\n"
        "    id: root\n"
        "    property real appear: 1\n"
        "    Behavior on opacity {\n"
        "        animation: Appearance.animation.elementMoveFast"
        ".numberAnimation.createObject(this)\n"
        "    }\n"
        "}\n"
    )
    nested_only = (
        "Button {\n"
        "    id: root\n"
        "    property real appear: 1\n"
        "    Rectangle {\n"
        "        Behavior on opacity {\n"
        "            animation: a\n"
        "        }\n"
        "    }\n"
        "}\n"
    )
    no_member = (
        "Item {\n"
        "    Behavior on opacity {\n"
        "        animation: a\n"
        "    }\n"
        "}\n"
    )
    if scan(offender) is None:
        return "the detector passes the planted root-level pair"
    if scan(nested_only) is not None:
        return "the detector flags a Behavior nested inside a child"
    if scan(no_member) is not None:
        return "the detector flags a file that declares no member"
    return None


def main():
    failure = self_check()
    if failure:
        print(f"Wave-member opacity-Behavior lint FAILED its self-check: "
              f"{failure}.", file=sys.stderr)
        return 1

    files = sorted(MODULES.rglob("*.qml"))
    members = []
    violations = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        has_member = any(ROOT_APPEAR.match(line)
                         for line in text.splitlines())
        if has_member:
            members.append(path)
        line = scan(text)
        if line is not None:
            violations.append((path.relative_to(MODULES), line))

    # The scan is only meaningful while the membership convention is what it
    # matches: RippleButton is the canonical root-level `appear` and must be
    # found, or the indentation assumption has rotted and everything below is
    # vacuous.
    expected = "common/widgets/RippleButton.qml"
    if expected not in {str(p.relative_to(MODULES)) for p in members}:
        print("Wave-member opacity-Behavior lint FAILED: the scan found no "
              f"root-level `property real appear` in {expected} - the "
              "indentation assumption or that file's shape changed, and the "
              "check below is now vacuous.", file=sys.stderr)
        return 1

    if violations:
        print("Wave-member opacity-Behavior lint FAILED: a wave member's "
              "opacity rides `appear`, so a root-level Behavior on opacity "
              "turns park()'s snap into an on-stage fade-out and freezes the "
              "entrance while `appear` animates. Delete the Behavior - the "
              "wave's own animation carries the curve:", file=sys.stderr)
        for rel, number in violations:
            print(f"  {rel}:{number}", file=sys.stderr)
        return 1

    print(f"Wave-member opacity-Behavior lint passed ({len(files)} QML "
          f"files, {len(members)} root-level wave members)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
