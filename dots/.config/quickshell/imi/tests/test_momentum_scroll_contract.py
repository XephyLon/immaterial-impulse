#!/usr/bin/env python3
"""Contract tests for the opt-in momentum (inertial trackpad) scroll.

Static checks, same style as the other suites here: read the QML sources and
assert the structural contracts that keep StyledFlickable's momentum path
working and isolated:

  - `momentumScroll` exists and defaults to false (opt-in only)
  - the WheelHandler is gated on it and accepts trackpad devices
  - the zero-delta finger-lift event (px === 0 && ang === 0) hands off to
    root.flick() with velocity clamped to maximumFlickVelocity
  - a classic mouse wheel (px === 0, real angleDelta) cancels the flick and
    does a plain discrete step - no inertia
  - the legacy fast-scroll MouseArea and the `Behavior on contentY` animation
    are BOTH disabled while momentum is on (they'd fight the flick)
  - an idle-gap fallback Timer exists, is restarted on every trackpad move,
    and launches the same clamped flick
  - every contentY write in the handler is clamped to [0, content bounds]
  - ContentPage opts in with momentumScroll: true

Blocks are sliced out by brace matching rather than flat substring checks, so
a regression that keeps the strings but moves them out of the WheelHandler
(or out of the right branch) still fails.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FLICKABLE = ROOT / "modules" / "common" / "widgets" / "StyledFlickable.qml"
CONTENT_PAGE = ROOT / "modules" / "common" / "widgets" / "ContentPage.qml"

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS {name}")
    else:
        print(f"  FAIL {name} {detail}")
        failures.append(name)


def read(path):
    return path.read_text(encoding="utf-8") if path.exists() else ""


def blocks(text, marker):
    """Yield every brace-balanced block starting at each occurrence of marker.

    marker is expected to be followed (possibly after whitespace) by '{'; the
    returned string spans from the marker through the matching '}'.
    """
    start = 0
    while True:
        i = text.find(marker, start)
        if i == -1:
            return
        j = text.find("{", i)
        if j == -1:
            return
        depth = 0
        for k in range(j, len(text)):
            if text[k] == "{":
                depth += 1
            elif text[k] == "}":
                depth -= 1
                if depth == 0:
                    yield text[i:k + 1]
                    break
        else:
            yield text[i:]
            return
        start = i + len(marker)


def first_block(text, marker, containing=""):
    for b in blocks(text, marker):
        if containing in b:
            return b
    return ""


def branch(text, condition):
    """Slice from a branch condition to its first `return;` (the branch body)."""
    i = text.find(condition)
    if i == -1:
        return ""
    j = text.find("return;", i)
    return text[i:j + len("return;")] if j != -1 else text[i:]


CLAMP_VELOCITY = re.compile(
    r"Math\.max\(\s*-root\.maximumFlickVelocity\s*,"
    r"\s*Math\.min\(\s*\w+\s*,\s*root\.maximumFlickVelocity\s*\)\s*\)"
)
CLAMP_CONTENT_Y = re.compile(
    r"root\.contentY\s*=\s*Math\.max\(\s*0\s*,\s*Math\.min\("
)


def main():
    print("Momentum scroll contract tests")

    flick = read(FLICKABLE)
    page = read(CONTENT_PAGE)
    check("StyledFlickable exists", FLICKABLE.exists())
    check("ContentPage exists", CONTENT_PAGE.exists())
    if not flick or not page:
        print("momentum scroll contract(s) failed: missing sources")
        return 1

    # --- Opt-in property ----------------------------------------------------
    check(
        "momentumScroll property defaults false",
        re.search(r"property\s+bool\s+momentumScroll\s*:\s*false", flick) is not None,
    )

    # --- WheelHandler block --------------------------------------------------
    wheel = first_block(flick, "WheelHandler {")
    check("WheelHandler block present", bool(wheel))
    check(
        "WheelHandler gated on momentumScroll",
        re.search(r"enabled\s*:\s*root\.momentumScroll\b", wheel) is not None,
    )
    check(
        "WheelHandler accepts trackpad devices",
        "acceptedDevices" in wheel and "PointerDevice.TouchPad" in wheel,
    )

    # Finger-lift branch: zero-delta scroll-stop event hands off to flick()
    lift = branch(wheel, "if (px === 0 && ang === 0)")
    check("finger-lift (zero-delta) branch present", bool(lift))
    check("finger-lift hands off via root.flick(", "root.flick(" in lift)
    check(
        "finger-lift velocity clamped to maximumFlickVelocity",
        CLAMP_VELOCITY.search(lift) is not None,
    )
    check(
        "finger-lift respects minimum velocity threshold",
        "momentumMinVelocity" in lift,
    )

    # Plain mouse-wheel branch: discrete step, no inertia
    after_lift = wheel[wheel.find(lift) + len(lift):] if lift else ""
    plain = branch(after_lift, "if (px === 0)")
    check("plain-wheel branch present (after finger-lift branch)", bool(plain))
    check("plain-wheel cancels any running flick", "cancelFlick" in plain)
    check(
        "plain-wheel does a discrete step from angleDelta",
        re.search(r"ang\s*/\s*120", plain) is not None
        and "mouseScrollFactor" in plain,
    )
    check(
        "plain-wheel contentY write clamped",
        CLAMP_CONTENT_Y.search(plain) is not None,
    )

    # Trackpad-move tail: 1:1 tracking + velocity + fallback timer restart
    tail = after_lift[after_lift.find(plain) + len(plain):] if plain else ""
    check("trackpad tail present", bool(tail))
    check("trackpad move cancels running flick", "cancelFlick" in tail)
    check(
        "trackpad contentY write clamped",
        CLAMP_CONTENT_Y.search(tail) is not None,
    )
    check(
        "trackpad move restarts idle-gap fallback timer",
        "momentumEndTimer.restart()" in tail,
    )

    # Every contentY assignment inside the handler must be clamped
    raw_writes = [
        line.strip()
        for line in wheel.splitlines()
        if re.search(r"root\.contentY\s*=", line)
        and not CLAMP_CONTENT_Y.search(line)
    ]
    check(
        "all WheelHandler contentY writes are clamped",
        not raw_writes,
        f"unclamped: {raw_writes}",
    )

    # --- Idle-gap fallback Timer ----------------------------------------------
    timer = first_block(flick, "Timer {", containing="momentumEndTimer")
    check("idle-gap fallback Timer exists", bool(timer))
    check("fallback timer flicks on trigger", "root.flick(" in timer)
    check(
        "fallback timer velocity clamped to maximumFlickVelocity",
        CLAMP_VELOCITY.search(timer) is not None,
    )
    check(
        "fallback timer respects minimum velocity threshold",
        "momentumMinVelocity" in timer,
    )

    # --- Competing scroll paths disabled while momentum is on ------------------
    fast_area = first_block(flick, "MouseArea {", containing="fasterTouchpadScroll")
    check("fast-scroll MouseArea present", bool(fast_area))
    fast_visible = re.search(r"visible\s*:\s*(.*)", fast_area)
    check(
        "fast-scroll MouseArea hidden when momentumScroll on",
        fast_visible is not None and "!root.momentumScroll" in fast_visible.group(1),
        f"visible: {fast_visible.group(1) if fast_visible else 'missing'}",
    )
    check(
        "fast-scroll MouseArea enabled follows visible",
        re.search(r"enabled\s*:\s*visible\b", fast_area) is not None,
    )

    behavior = first_block(flick, "Behavior on contentY")
    check("Behavior on contentY present", bool(behavior))
    behavior_enabled = re.search(r"enabled\s*:\s*(.*)", behavior)
    check(
        "contentY Behavior disabled when momentumScroll on",
        behavior_enabled is not None
        and "!root.momentumScroll" in behavior_enabled.group(1),
        f"enabled: {behavior_enabled.group(1) if behavior_enabled else 'missing'}",
    )

    # --- ContentPage opts in ------------------------------------------------
    check(
        "ContentPage opts in with momentumScroll: true",
        re.search(r"^\s*momentumScroll\s*:\s*true\b", page, re.MULTILINE) is not None,
    )

    if failures:
        print(f"{len(failures)} momentum scroll contract(s) failed")
        return 1
    print("All momentum scroll contract tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
