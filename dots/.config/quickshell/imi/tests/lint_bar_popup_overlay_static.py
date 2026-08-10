#!/usr/bin/env python3
"""The bar popup overlay's surface geometry must be a constant of the screen.

`modules/imi/bar/BarPopupOverlay.qml` hosts every bar popup's card on one
always-mapped layer surface. That only works while the *surface* never moves or
resizes: on a layer-shell surface position is `margins`, so a bound margin, a
bound implicit size, or an edge anchor that can go false reconfigures the
surface - which is the create-map-destroy loop StyledPopup's imperative
positioning was written to escape, reached from the other side.

Two more properties this file must keep, both from the same design:

  - the mask tracks x/y/width/height and *not* transforms, so the morph and the
    exit may never be expressed as `scale` or `rotation` (quickshell
    src/core/region.cpp connects only the four geometry signals);
  - the card must collapse to 0x0 when idle, because an `opacity: 0` card still
    publishes a full-size input region and would eat every click in its
    rectangle for the rest of the session.

Run from `tests/run_tests.sh`. Prove it can fail by planting one of the banned
forms in a clean tree.
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OVERLAY = HERE.parent / "modules/imi/bar/BarPopupOverlay.qml"

failures = []

if not OVERLAY.exists():
    print(f"{OVERLAY}: missing", file=sys.stderr)
    sys.exit(1)

source = OVERLAY.read_text(encoding="utf-8")
code = re.sub(r"//.*", "", source)

# A `margins { ... }` group or any `margins.<edge>:` assignment is the surface
# telling the compositor where to put itself.
if re.search(r"(?<!\.)\bmargins\s*\{", code) or re.search(r"(?<!\.)\bmargins\.\w+\s*:", code):
    failures.append("declares layer-shell margins; the surface's position must be a constant")

for prop in ("implicitWidth", "implicitHeight"):
    if re.search(rf"\b{prop}\s*:", code):
        failures.append(f"declares {prop}; the surface must not size itself from its contents")

anchors = re.search(r"anchors\s*\{(.*?)\}", code, re.DOTALL)
if not anchors:
    failures.append("has no anchors block; the surface must be anchored to all four screen edges")
else:
    for edge in ("top", "bottom", "left", "right"):
        if not re.search(rf"\b{edge}\s*:\s*true\b", anchors.group(1)):
            failures.append(f"anchors.{edge} is not literally true")

for transform in ("scale", "rotation"):
    if re.search(rf"^\s*{transform}\s*:", code, re.MULTILINE) \
            or re.search(rf"Behavior\s+on\s+{transform}\b", code):
        failures.append(
            f"animates {transform}; a Region does not track transforms, so the mask would "
            "stop matching the card")

for axis in ("width", "height"):
    if not re.search(rf"^\s*{axis}\s*:\s*0\b", code, re.MULTILINE):
        failures.append(f"the card does not start at {axis} 0")
    if not re.search(rf"\bcard\.{axis}\s*=\s*0\b", code):
        failures.append(
            f"never collapses the card back to {axis} 0; an exited card must build an empty "
            "input region, and an opacity-0 card still publishes a full-size one")

if 'WlrLayershell.namespace: "quickshell:barPopup"' not in code:
    failures.append(
        'does not use the quickshell:barPopup namespace, which rules.lua gives the computed '
        'popup-blur threshold; a namespace outside that loop falls through to the '
        "catch-all ignore_alpha and asks the compositor to blur the whole screen")

if "WindowBlurRegion" in code:
    failures.append(
        "publishes a WindowBlurRegion; quickshell:popup already blurs an opaque body through "
        "ignore_alpha = 1 and a region there would be the only source of blur")

# A per-popup barEdge watcher fires on a freshly built popup's first binding
# evaluation, which is indistinguishable from an orientation flip: it ran
# finishExit() during the takeover that was building the card and left the popup
# as a 20x20 dot, so whether the popup opened at all came down to a race. Every
# popup derives barEdge from the same global config, so the overlay derives it
# once itself.
if "function onBarEdgeChanged" in code:
    failures.append(
        "watches barEdge on the current popup; a popup rebuilt per open evaluates that binding "
        "after the Connections attaches and the initial evaluation tears the card down mid-takeover")

if "readonly property string barEdge:" not in code:
    failures.append("does not derive barEdge from the config itself")

if failures:
    for failure in failures:
        print(f"modules/imi/bar/BarPopupOverlay.qml: {failure}", file=sys.stderr)
    sys.exit(1)

print("Bar popup overlay lint passed: the overlay surface's geometry is a constant")
sys.exit(0)
