#!/usr/bin/env python3
"""The bar popup overlay's surface geometry must be a constant of the screen.

`modules/imi/bar/BarPopupOverlay.qml` hosts every bar popup's card on one
layer surface. That only works while the *surface* never moves or resizes: on a
layer-shell surface position is `margins`, so a bound margin, a bound implicit
size, or an edge anchor that can go false reconfigures the surface - which is
the create-map-destroy loop StyledPopup's imperative positioning was written to
escape, reached from the other side.

The surface is no longer always MAPPED - it unmaps while it has nothing to
show, because a mapped screen-sized Overlay surface holds the compositor's
fullscreen fast path shut - and that added a rule of its own. A WlrLayershell
window that has just gone visible does not have its size yet: measured on the
live compositor, 500x500 for the same tick and through Qt.callLater, the real
size arriving with the configure ~50ms later. `retarget()` clamps the card
against the window's width/height, so a retarget on the zero-interval timer
alone pinned the card to the top-left margin - the calendar under the clock at
screen-centre. The overlay must therefore retarget again when its own geometry
lands (`onWidthChanged`/`onHeightChanged`), which is the last check below.

Two more properties this file must keep, both from the same design:

  - the mask tracks x/y/width/height and *not* transforms, so the morph and the
    exit may never be expressed as `scale` or `rotation` (quickshell
    src/core/region.cpp connects only the four geometry signals);
  - the card must collapse to 0x0 when idle, because an `opacity: 0` card still
    publishes a full-size input region and would eat every click in its
    rectangle for the rest of the session.

THE DRIVER, which is the last group of checks.

The card runs on ONE `real` 0 -> 1, `openProgress`. The fade rides it and so
does the hero-height unroll, and everything else that scalar can produce is a
binding on it rather than a second animation - a quantity carried by two
animations is two timings that agree at rest, which is the only place anybody
looks, and disagree exactly mid-flight. So the checks below refuse a `Behavior`
on anything the driver already carries, refuse a second one on the driver
itself, and require the height and the opacity to be derived from it.

The height is a plain binding rather than a Behavior for a second reason: a
Behavior whose target moves every frame restarts every frame and never ticks
(b710ef731 ("fix(plugins): stop the position Behavior swallowing the parallax
cancellation")). The card's bar-adjacent coordinate is a function of that
height, so on the bottom and right edges an animated height would be exactly
that shape.

The unroll's start height is the height of the content's FIRST drawn section,
measured through `bar_popup_unroll.js` once the content has been parented - not
a literal and not the parked square. A literal there is the failure the whole
technique exists to avoid: it renders, it looks deliberate, and it is wrong for
every popup but the one it was tuned against.

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

# The window retargets when its OWN geometry arrives. Without this the first
# retarget after unmap->map runs against the placeholder 500x500 and the clamp
# pins the card to the margin.
for signal in ("onWidthChanged", "onHeightChanged"):
    if not re.search(rf"^\s*{signal}:\s*if \(overlayWindow\.current\) overlayWindow\.retarget\(\)",
                     code, re.MULTILINE):
        failures.append(
            f"does not retarget on the window's {signal}; a just-shown layer surface "
            f"reports a placeholder size for its first tick and the clamp pins the card "
            f"to the top-left margin")

for transform in ("scale", "rotation"):
    if re.search(rf"^\s*{transform}\s*:", code, re.MULTILINE) \
            or re.search(rf"Behavior\s+on\s+{transform}\b", code):
        failures.append(
            f"animates {transform}; a Region does not track transforms, so the mask would "
            "stop matching the card")

# The card's height is derived from the driver, so the two properties that must
# start at and return to zero are the inputs that produce it: a zero open height
# is zero at every progress, including one the exit's curve has undershot past.
for axis in ("width", "openHeight"):
    if not re.search(rf"^\s*(?:property real )?{axis}\s*:\s*0\b", code, re.MULTILINE):
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

# --- the one driver, and what may not be animated beside it -------------------

DRIVER = "openProgress"


def block_from(text, brace):
    """The body of the brace block opening at `brace`."""
    depth = 0
    for index in range(brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:index]
    return ""


def block_declaring(text, ident):
    """The body of the object declaring `id: <ident>`."""
    marker = re.search(rf"\bid:\s*{ident}\b", text)
    if not marker:
        return ""
    brace = text.rfind("{", 0, marker.start())
    return block_from(text, brace) if brace >= 0 else ""


# The shadow follows the card and reads its opacity, so "which opacity" has to
# be answered by position rather than by the first match in the file.
card = block_declaring(code, "card")
if not card:
    failures.append("has no `id: card` object; the whole design is one card on one surface")

if not re.search(rf"^\s*property real {DRIVER}\s*:\s*0\b", code, re.MULTILINE):
    failures.append(
        f"declares no `property real {DRIVER}: 0`; the card's motion is one scalar and "
        "the checks below are about what may be derived from it")

behaviors = re.findall(r"Behavior\s+on\s+(\w+)", code)

if behaviors.count(DRIVER) != 1:
    failures.append(
        f"carries {behaviors.count(DRIVER)} Behaviors on {DRIVER}; the driver is one scalar "
        "with one transition, and a second one is a second timing that agrees only at rest")

# `height` and `opacity` ARE the driver, expressed. `x` and `y` are functions of
# the size it produces on the two far bar edges, so an animation on either is
# the same defect one step removed.
for derived in ("height", "opacity", "x", "y"):
    if derived in behaviors:
        failures.append(
            f"animates {derived} with a Behavior; that value is derived from {DRIVER}, and "
            f"two animations of one quantity disagree exactly mid-flight - for height it is "
            f"also a target that moves every frame, which restarts every frame and never ticks")

# A Behavior taking a bare NumberAnimation is half a motion tier: it names a
# duration and leaves easing.type at Qt's default, which is Easing.Linear.
for behavior in re.finditer(r"Behavior\s+on\s+\w+\s*\{", code):
    body = block_from(code, behavior.end() - 1)
    if re.search(r"\b(NumberAnimation|PropertyAnimation)\s*\{", body):
        failures.append(
            f"declares an inline animation in `{behavior.group(0).strip()}`; take the motion "
            "tier whole through its own numberAnimation component, or the curve is whatever "
            "Qt defaults to")

if not re.search(r"numberAnimation\.createObject\(", code):
    failures.append("takes no motion tier through its own numberAnimation component")

# The height and the fade must both be the driver, spelled out. Read as whole
# declarations rather than as lines: both are written across two lines here, and
# a line-scoped check sees `height: BarPopupUnroll.cardHeight(` and stops.
def declaration(text, name):
    match = re.search(rf"^([ \t]*){name}:[ \t]*(.*(?:\n\1[ \t]+.*)*)", text, re.MULTILINE)
    return match.group(2) if match else ""


height_binding = declaration(card, "height")
if "BarPopupUnroll.cardHeight(" not in height_binding or f"card.{DRIVER}" not in height_binding:
    failures.append(
        f"the card's height is not a binding on {DRIVER} through bar_popup_unroll.js; the "
        "unroll and the fade must be the same scalar or they are two motions")

if f"card.{DRIVER}" not in declaration(card, "opacity"):
    failures.append(
        f"the card's opacity is not derived from {DRIVER}; the fade rides the same progress "
        "as the unroll")

# The hero is measured, never chosen. Zeroing it is how the card is idled, so
# the only literal allowed on that property is 0.
if not re.search(r"card\.heroHeight\s*=\s*BarPopupUnroll\.heroSectionHeight\(", code):
    failures.append(
        "does not measure the unroll's start height from the content's first section; a "
        "literal hero renders, looks deliberate, and is wrong for every popup but one")

for literal in re.findall(r"card\.heroHeight\s*=\s*([0-9][\w.]*)", code):
    if literal != "0":
        failures.append(
            f"assigns a literal hero height ({literal}); the card opens at the height of the "
            "section it is showing, which only the content can answer")

# Measuring the incoming content before it is parented reads a stale implicit
# size, so the first correct target is one turn of the event loop away.
if not re.search(r"interval:\s*0\b[\s\S]{0,120}?onTriggered:[^\n]*retarget\(\)", code):
    failures.append(
        "has no zero-interval retarget; an unparented content tree does not polish, so its "
        "implicit size - and its first section's height - are stale until the turn after "
        "the takeover")

if failures:
    for failure in failures:
        print(f"modules/imi/bar/BarPopupOverlay.qml: {failure}", file=sys.stderr)
    sys.exit(1)

print("Bar popup overlay lint passed: the overlay surface's geometry is a constant")
sys.exit(0)
