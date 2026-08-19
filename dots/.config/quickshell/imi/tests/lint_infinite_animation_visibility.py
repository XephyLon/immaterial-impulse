#!/usr/bin/env python3
#
# Regression guard: an animation that loops forever must stop when the thing it
# animates is not on screen.
#
# The chain that makes this expensive is not obvious from the animation. A
# running animation writes a property every frame; a written property dirties
# the scene; a dirty scene makes the shell commit a frame; and a commit makes
# the COMPOSITOR repaint the whole output. So one forgotten spinner keeps a
# 5120x1440 240Hz screen redrawing forever - including while the desktop it
# lives on is completely hidden behind a fullscreen window, where nobody could
# see it anyway.
#
# That is not a micro-optimisation. Measured against FINAL FANTASY XIV's own
# frame counter, fullscreen on a static scene, with the shell otherwise
# untouched:
#
#     shell not running at all                       108 fps
#     shell running, cookie clock spinning            52 fps
#     shell running, the spin gated on `visible`      94 fps
#
# The user reported it as "my game's FPS is halved when qs is running even in
# fullscreen", and it was: one `RotationAnimation` with `loops:
# Animation.Infinite` in `CookieClock.qml`, doing 30 seconds per turn, behind
# an opaque game.
#
# THE RULE: every `loops: Animation.Infinite` is gated on `visible` - either
# directly in its own `running:`, or through a `property bool` in the same file
# that is itself gated. `visible` is EFFECTIVE visibility in QML (false while
# any ancestor is hidden), which is what makes it the right question: the
# animation does not have to know why it is off screen.
#
# THE REGISTER, and why it is a ratchet. Nine of these live on surfaces that are
# unmapped when they are not showing (the region selector, the recording panel,
# the overview's search bar, a loading indicator), where the animation stops
# with the surface and the gate would be a no-op. They are registered rather
# than swept because each needs its own reading of what "showing" means there,
# and an unverified sweep of nine animations is how a spinner ends up frozen on
# screen. The register fails both ways: a new ungated animation outside it, and
# a registered file that gains its gate and is not removed.

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1] / "modules"

INFINITE = "Animation.Infinite"
RUNNING = re.compile(r"running:\s*([^\n]+)")
BOOL_PROPERTY = re.compile(r"property\s+bool\s+(\w+)\s*:\s*([^\n]+(?:\n\s+&&[^\n]+)*)")

EXISTING = frozenset({
})


def gated(lines, index, gated_properties):
    """Is the animation whose `loops:` is at `index` gated on visibility?"""
    depth = 0
    start = index
    for j in range(index, max(-1, index - 40), -1):
        depth += lines[j].count("}") - lines[j].count("{")
        if depth < 0:
            start = j
            break
    body = "\n".join(lines[start:index + 12])
    match = RUNNING.search(body)
    if not match:
        return False
    expression = match.group(1)
    if "visible" in expression:
        return True
    # One level of indirection: `running: shape.spinning`, where `spinning` is
    # a bool property in the same file that carries the visibility term.
    return any(name in expression for name in gated_properties)


def main():
    failures = []
    ungated = set()
    scanned = 0

    for path in sorted(ROOT.rglob("*.qml")):
        text = path.read_text(encoding="utf-8")
        if INFINITE not in text:
            continue
        relative = str(path.relative_to(ROOT))
        lines = text.splitlines()
        gated_properties = {name for name, value in BOOL_PROPERTY.findall(text)
                            if "visible" in value}
        for index, line in enumerate(lines):
            if INFINITE not in line:
                continue
            scanned += 1
            if gated(lines, index, gated_properties):
                continue
            ungated.add(relative)
            if relative in EXISTING:
                continue
            failures.append(
                f"{relative}:{index + 1}: loops forever with no visibility term. "
                f"A running animation dirties the scene every frame, and every "
                f"frame the shell commits makes the compositor repaint the whole "
                f"output - one of these behind a fullscreen game cost it half "
                f"its frames. Gate `running:` on `visible` (effective "
                f"visibility, so it covers every ancestor that hides this).")

    for relative in sorted(EXISTING - ungated):
        if not (ROOT / relative).exists():
            failures.append(f"{relative}: registered and no longer present. "
                            f"Drop it from EXISTING.")
            continue
        failures.append(
            f"{relative}: every infinite animation in it is gated now. Remove it "
            f"from EXISTING in tests/lint_infinite_animation_visibility.py - the "
            f"register is a ratchet, and one that is not tightened stops being "
            f"read.")

    if failures:
        print("Infinite animation visibility lint failed:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print(f"Infinite animation visibility lint passed ({scanned} infinite "
          f"animations, {len(ungated)} registered files still ungated)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
