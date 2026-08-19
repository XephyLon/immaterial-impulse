#!/usr/bin/env python3
#
# Regression guard: a duration read out of `Appearance.animationCurves` is a
# tier's BASE, and the shell's speed setting is not in it.
#
#   duration: Appearance.animationCurves.expressiveFastSpatialDuration
#
# names a token, carries no millisecond literal, and pairs correctly with that
# tier's own curve - so `lint_motion_tier_partial.py` passes it, review passes
# it, and `docs/M3_GUIDELINES.md` §2's rule about raw durations is satisfied.
# What it skips is `modules/common/motion_policy.js`: `Appearance.animation.*`
# applies the multiplier and the reduce-motion floor, `animationCurves.*` is
# what those are applied TO. Every such read is an animation the speed slider
# and the accessibility switch cannot reach, silently, in a shell where
# 954a7885a ("feat(motion): one policy for the speed, the floor and the
# stagger") exists precisely so that they can.
#
# Eight sites read a base duration this way when the check was written, plus a
# ninth - `designsystem/widgets/shapes/ShapeCanvas.qml` - that had the number
# and the curve written out by hand, so a shape morph was the one animation in
# the shell that could not be retimed at all. That one was found by a survey
# rather than by anything in the suite
# (docs/p3drovfx-animation-research-2026-08-16.md §7, finding 4), which is the
# argument for a check: the defect is invisible in the source and invisible on
# screen until someone moves the slider and half the shell ignores it.
#
# Two spellings are accepted, and the difference between them is the point:
#
#   - `Appearance.animation.<tier>.duration` - the tier, scaled. Right whenever
#     the animation also takes that tier's curve.
#   - `Appearance.animation.scale(Appearance.animationCurves.<x>Duration)` -
#     the policy's own door, for a duration deliberately paired with a
#     DIFFERENT tier's curve (StyledFlickable's rubber band, the recording
#     panel's pulse). Borrowing whichever tier happens to share the number
#     would tie those to a curve they do not use.
#
# `Appearance.qml` itself is exempt: it is where the scaling is applied.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POLICY_OWNER = "modules/common/Appearance.qml"

# `Appearance.animationCurves.<name>Duration`, optional chaining allowed at
# every hop the way the rest of the tree writes it.
BASE_DURATION = re.compile(
    r"\bAppearance\s*\??\s*\.\s*animationCurves\s*\??\s*\.\s*(\w+Duration)\b")
# The policy's door, with the base read as its argument.
SCALED = re.compile(
    r"\bAppearance\s*\??\s*\.\s*animation\s*\??\s*\.\s*scale\s*\(\s*"
    r"Appearance\s*\??\s*\.\s*animationCurves\s*\??\s*\.\s*\w+Duration\s*\)")


def bypasses(text: str):
    """(line, token) for every base duration read that is not scaled."""
    scaled_spans = [match.span() for match in SCALED.finditer(text)]
    found = []
    for match in BASE_DURATION.finditer(text):
        if any(start <= match.start() and match.end() <= end
               for start, end in scaled_spans):
            continue
        found.append((text.count("\n", 0, match.start()) + 1, match.group(1)))
    return found


FIXTURE_BYPASS = """
Item {
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animationCurves.expressiveEffectsDuration
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }
}
"""

FIXTURE_CLEAN = """
Item {
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on width {
        NumberAnimation {
            duration: Appearance.animation.scale(Appearance.animationCurves.expressiveEffectsDuration)
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }
    Behavior on height {
        NumberAnimation {
            duration: 200
            easing.bezierCurve: Appearance.animationCurves.standard
        }
    }
}
"""


def self_check() -> list:
    """Prove the machinery independently of what the tree contains.

    The second fixture is the one that earns its place: a check written as a
    bare search for `animationCurves.*Duration` reports the scaled spelling as
    an offender, which would make the honest fix for a mixed duration/curve
    pair impossible to write.
    """
    problems = []
    if len(bypasses(FIXTURE_BYPASS)) != 1:
        problems.append("self-check: an unscaled base duration was not detected")
    if bypasses(FIXTURE_CLEAN):
        problems.append(
            "self-check: a scaled tier, the policy's scale() door or a literal "
            "duration was reported as a bypass")
    return problems


def main() -> int:
    failures = self_check()
    scanned = 0

    for path in sorted(ROOT.rglob("*.qml")):
        relative = path.relative_to(ROOT).as_posix()
        if relative.startswith("tests/") or relative == POLICY_OWNER:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        scanned += 1
        for line, token in bypasses(text):
            failures.append(
                f"{relative}:{line}: reads `animationCurves.{token}`, which is "
                f"the tier's base - the motion multiplier and the reduce-motion "
                f"floor are applied by `Appearance.animation.*`, so this "
                f"animation ignores both. Take the matching tier "
                f"(`Appearance.animation.<tier>.duration`), or, where the "
                f"curve deliberately comes from a different tier, scale it "
                f"through the policy's own door: "
                f"`Appearance.animation.scale(Appearance.animationCurves.{token})`.")

    if not scanned:
        failures.append("no QML files scanned - the sweep is looking in the wrong place")

    for failure in failures:
        print(f"motion multiplier bypass: {failure}", file=sys.stderr)
    if failures:
        return 1
    print(f"Motion multiplier bypass lint passed: {scanned} QML files, every "
          f"catalogued duration goes through the policy")
    return 0


if __name__ == "__main__":
    sys.exit(main())
