#!/usr/bin/env python3
"""Contract tests for dock feedback motion (M3 Expressive).

Static checks, same style as the other suites here: read the QML sources and
assert the structural contracts that keep the dock's motion token-driven and
consistent across pinned (DragApps) and unpinned (DockAppButton) buttons.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRACKER = ROOT / "services" / "DockLaunchTracker.qml"
MOTION = ROOT / "modules" / "common" / "widgets" / "DockIconMotion.qml"
DOCK_APP_BUTTON = ROOT / "modules" / "common" / "widgets" / "DockAppButton.qml"
DRAG_APPS = ROOT / "modules" / "common" / "widgets" / "DragApps.qml"

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS {name}")
    else:
        print(f"  FAIL {name} {detail}")
        failures.append(name)


def read(path):
    return path.read_text(encoding="utf-8") if path.exists() else ""


def main():
    print("Dock motion contract tests")

    # --- DockLaunchTracker ---
    tracker = read(TRACKER)
    check("tracker exists", TRACKER.exists())
    check("tracker is a singleton", "pragma Singleton" in tracker)
    for fn in ("markLaunching", "isLaunching", "clearLaunching", "firstAppearance"):
        check(f"tracker defines {fn}", f"function {fn}(" in tracker)
    check("tracker has a timeout", "timeoutMs" in tracker and "Timer" in tracker)
    check(
        "tracker clears on window map",
        "onAppsChanged" in tracker and "TaskbarApps" in tracker,
    )

    # --- DockIconMotion ---
    motion = read(MOTION)
    check("motion component exists", MOTION.exists())
    for prop in ("hovered", "pressed", "launching", "dragging"):
        check(f"motion has {prop} input", f"property bool {prop}" in motion)
    check("motion has playAppear", "function playAppear(" in motion)
    raw_durations = [
        m
        for m in re.finditer(r"duration:\s*(\d+)", motion)
        if m.group(1) != "0"
    ]
    check(
        "motion durations are token-only",
        not raw_durations,
        f"raw literals: {[m.group(0) for m in raw_durations]}",
    )
    check(
        "motion curves are token-only",
        "bezierCurve" not in motion
        or "Appearance.animationCurves" in motion,
    )
    check(
        "motion never animates layout size",
        "Behavior on implicitWidth" not in motion
        and "Behavior on implicitHeight" not in motion
        and "Behavior on width" not in motion
        and "Behavior on height" not in motion,
    )

    # --- Consumers ---
    dab = read(DOCK_APP_BUTTON)
    da = read(DRAG_APPS)
    check("DockAppButton uses DockIconMotion", "DockIconMotion" in dab)
    check("DragApps uses DockIconMotion", "DockIconMotion" in da)
    check("DockAppButton marks launches", "DockLaunchTracker.markLaunching" in dab)
    check("DragApps marks launches", "DockLaunchTracker.markLaunching" in da)
    check("DragApps suppresses motion while dragging", "dragging:" in da)
    check(
        "DockAppButton dots spring (width)",
        "Behavior on implicitWidth" in dab,
    )
    check("DockAppButton dots spring (color)", "Behavior on color" in dab)
    check("DragApps dots spring (width)", "Behavior on implicitWidth" in da)
    check("DragApps dots spring (color)", "Behavior on color" in da)

    if failures:
        print(f"{len(failures)} dock motion contract(s) failed")
        return 1
    print("All dock motion contract tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
