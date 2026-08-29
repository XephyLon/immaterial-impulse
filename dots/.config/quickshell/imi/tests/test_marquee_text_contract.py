#!/usr/bin/env python3
#
# Contract for the one marquee in this shell, and for where it is allowed to
# run.
#
# A marquee is an animation with `loops: Animation.Infinite` sitting on a
# label, which is the exact shape that cost a fullscreen game half its frames
# (see tests/lint_infinite_animation_visibility.py, and AGENT.md's
# design-language section). That lint holds the general rule and carries a
# seven-file ratchet; this file holds the four things it cannot see:
#
#   1. The gate is `overflows && visible`, not `visible` alone. A marquee that
#      runs whenever it is on screen runs on every label that already fits,
#      writing `x` sixty times a second to move a string nobody asked to move.
#      The generic lint passes that happily - it only asks whether the word
#      `visible` is reachable from `running:`.
#   2. MarqueeText is not in that lint's register. The register is for
#      animations whose surface is unmapped when idle and whose gate would be a
#      no-op; a marquee is adopted on such surfaces DELIBERATELY, so it must
#      carry its gate anyway rather than lean on the surface.
#   3. The travel is scaled and the dwell is not. Both halves fail silently and
#      in opposite directions: an unscaled travel is an animation the speed
#      slider and the reduce-motion switch cannot reach, and a scaled dwell is
#      zero at the reduce-motion floor - where the travel is also zero - so the
#      accessibility state would produce a label swapping its two ends every
#      frame. That is a photosensitivity hazard reached by asking for less
#      motion.
#   4. The adoption set. Every call site is reviewed, because "this string is
#      an identity the user cannot look up elsewhere" is a judgement no pattern
#      can make, and because a marquee on a surface the compositor merely
#      COVERS (the bar: WlrLayer.Top, `visible` stays true under a fullscreen
#      window - 53d1ff893) is the perf bug wearing the fix's clothes.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contract_runner import run  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
WIDGET = ROOT / "modules/common/widgets/MarqueeText.qml"
INFINITE_LINT = ROOT / "tests/lint_infinite_animation_visibility.py"

# path (repo-relative, POSIX) -> why elision loses information there. Adding a
# row is the review: name the string, and name the surface it sits on, which
# must be one that is unmapped or hidden when idle.
REVIEWED_ADOPTIONS = {
    "modules/imi/dock/DragApps.qml":
        "the dock's window-preview card - the title is the only thing telling "
        "several windows of one application apart, and the popup is an "
        "xdg-popup that does not exist while it is not shown",
    "modules/imi/sidebarRight/wifiNetworks/WifiNetworkItem.qml":
        "an SSID, on the right sidebar - a layer surface whose `visible` is "
        "false whenever the sidebar is closed",
    "modules/imi/sidebarRight/bluetoothDevices/BluetoothDeviceItem.qml":
        "a paired device's advertised name, on the same surface",
    "modules/imi/sidebarRight/volumeMixer/VolumeMixerEntry.qml":
        "a stream's media name, on the same surface - elision here removes "
        "exactly the half that identifies the stream",
}

USE = re.compile(r"(?:^|[^\w.])MarqueeText\s*\{")
BOOL_PROPERTY = re.compile(r"property\s+bool\s+(\w+)\s*:\s*([^\n]+)")
SCALE_CALL = r"Appearance\s*\??\s*\.\s*animation\s*\??\s*\.\s*scale\s*\(\s*"

# Both duration declarations in this widget are written across two lines, and a
# line-scoped check reads `duration: Appearance.animation.scale(` and finds no
# travel duration at all - the same trap 189caa6ff's sweep records for a
# block-bodied QML property. Whitespace is flattened first so a declaration is
# matched whole, however it is wrapped.
def flat(source: str) -> str:
    return re.sub(r"\s+", " ", source)


def widget_source() -> str:
    return WIDGET.read_text(encoding="utf-8")


def _running_expression(source: str) -> str:
    for line in source.splitlines():
        stripped = line.strip()
        if stripped.startswith("running:"):
            return stripped.split(":", 1)[1].strip()
    return ""


def gate_terms(source: str) -> str:
    """The full expression the infinite animation's `running:` resolves to."""
    expression = _running_expression(source)
    for name, value in BOOL_PROPERTY.findall(source):
        if name in expression:
            return value
    return expression


def test_the_widget_exists_and_loops_forever():
    assert WIDGET.exists(), f"{WIDGET} is missing - the rest of this contract is vacuous"
    source = widget_source()
    assert "Animation.Infinite" in source, (
        "MarqueeText no longer loops forever. If the scroll became a one-shot "
        "this whole contract needs rewriting rather than deleting - say so.")


def test_the_scroll_is_gated_on_visibility_and_on_overflowing():
    gate = gate_terms(widget_source())
    assert "visible" in gate, (
        f"the marquee's `running:` resolves to `{gate}`, which carries no "
        "visibility term. A running animation dirties the scene every frame "
        "and the compositor repaints the whole output for it.")
    assert "overflows" in gate, (
        f"the marquee's `running:` resolves to `{gate}`, which does not ask "
        "whether the text overflows. A marquee that runs on a label that "
        "already fits animates a string nobody asked to move - and the "
        "infinite-animation lint cannot see it, because the visibility term "
        "is there.")


def test_the_widget_does_not_join_the_infinite_animation_ratchet():
    register = INFINITE_LINT.read_text(encoding="utf-8")
    assert "MarqueeText.qml" not in register, (
        "MarqueeText is registered as an ungated infinite animation in "
        "lint_infinite_animation_visibility.py. That register is for "
        "animations on surfaces that are unmapped when idle, where the gate "
        "would be a no-op; a marquee is adopted on exactly those surfaces on "
        "purpose, so it carries its own gate rather than leaning on them.")


def test_the_travel_goes_through_the_motion_policy():
    body = flat(widget_source())
    assert "Marquee.travelDuration(" in body, (
        "MarqueeText no longer reads a travel duration at all")
    assert re.search(r"duration:\s*" + SCALE_CALL + r"Marquee\.travelDuration\(", body), (
        "the travel duration does not go straight through "
        "`Appearance.animation.scale()`, so the speed slider and the "
        "reduce-motion switch never reach the one animation in the shell that "
        "runs for as long as its label is on screen.")


def test_the_dwell_is_not_scaled():
    body = flat(widget_source())
    assert "Marquee.dwell(" in body, (
        "MarqueeText no longer takes its dwell from marquee.js, so the "
        "reduce-motion hold is not decided anywhere a test can reach")
    assert not re.search(SCALE_CALL + r"Marquee\.dwell\(", body), (
        "the dwell is scaled. At the reduce-motion floor every catalogued "
        "duration is 0 - including the traverse this dwell brackets - so a "
        "scaled dwell makes the label swap its two ends every frame. Asking "
        "for less motion would produce the most aggressive motion in the "
        "shell.")
    assert re.search(r"duration:\s*Marquee\.dwell\(", body), (
        "the dwell no longer reaches its PauseAnimation directly. Anything "
        "between the two is where a scaling gets reintroduced.")


def test_the_label_does_not_elide():
    source = widget_source()
    assert "elide: Text.ElideNone" in source, (
        "MarqueeText's label must declare `elide: Text.ElideNone`. An eliding "
        "label shortens itself to its box, so the marquee scrolls a string "
        "that already ends in an ellipsis - the motion is there and the "
        "information is not, which is the failure this widget exists to fix "
        "wearing its own fix's clothes.")


def _adoptions() -> dict:
    found = {}
    for path in sorted(ROOT.rglob("*.qml")):
        relative = path.relative_to(ROOT).as_posix()
        if relative.startswith("tests/") or path == WIDGET:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        uses = len(USE.findall(text))
        if uses:
            found[relative] = uses
    return found


def test_every_adoption_is_reviewed():
    for relative in sorted(_adoptions()):
        assert relative in REVIEWED_ADOPTIONS, (
            f"{relative} adopts MarqueeText without a review. Add it to "
            "REVIEWED_ADOPTIONS in tests/test_marquee_text_contract.py with "
            "the string it shows and the surface it sits on. Two questions "
            "have to be answered there and neither is checkable: is the "
            "elided string an IDENTITY the user cannot recover elsewhere, and "
            "is the surface one that is hidden when idle? The bar is not - it "
            "is on WlrLayer.Top and stays `visible` under a fullscreen window "
            "that covers it (53d1ff893).")


def test_the_review_register_carries_no_dead_entries():
    adopted = _adoptions()
    for relative in sorted(REVIEWED_ADOPTIONS):
        assert relative in adopted, (
            f"{relative} is registered as a marquee call site and no longer "
            "declares one. Drop it from REVIEWED_ADOPTIONS - a register with "
            "slack in it stops being read.")


def test_the_arithmetic_is_not_written_out_in_the_widget():
    source = widget_source()
    for number, line in enumerate(source.splitlines(), 1):
        if line.lstrip().startswith("//"):
            continue
        assert "implicitWidth >" not in line and "implicitWidth -" not in line, (
            f"MarqueeText.qml:{number}: the overflow test or the travel "
            "distance is spelled out here. Both belong in marquee.js, which "
            "is the only part of this widget a check can reach - "
            "`qmltestrunner` can build neither a StyledText nor a laid-out "
            "box.")


if __name__ == "__main__":
    sys.exit(run(globals()))
