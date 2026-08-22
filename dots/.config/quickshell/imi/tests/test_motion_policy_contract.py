#!/usr/bin/env python3
"""One motion policy, reached through one door.

`modules/common/motion_policy.js` decides three things - how a catalogued
duration is scaled, where the reduce-motion floor is, and how a group of things
arrives in sequence. `tests/tst_motion_policy.qml` pins the arithmetic and
`tests/test_motion_multiplier_runtime.py` pins that the shell really reads it.
What is left, and what this file holds, is the part that decays quietly: that
every tier still goes through it, that the module stays pure enough to be
testable at all, and that a cascade written next year does not spell its own
`index * 40` beside the one that does not.

The failure this guards against is the surveyed fork's, restated: it HAS an
animation multiplier, and roughly half its shell does not see it, because the
value of a knob is exactly the proportion of the tree that routes through it -
and that proportion only ever decays.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contract_runner import run  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "modules/common/motion_policy.js"
APPEARANCE = ROOT / "modules/common/Appearance.qml"
CONFIG = ROOT / "modules/common/Config.qml"
SETTINGS_PAGE = ROOT / "modules/imi/settings/pages/AppearanceConfig.qml"
EXPANDABLE_PANEL = ROOT / "modules/common/widgets/ExpandablePanel.qml"
CAROUSEL = ROOT / "modules/common/plugins/designsystem/widgets/Carousel.qml"
STAGGER_WAVE = ROOT / "modules/common/widgets/StaggerWave.qml"

# `Appearance.animation`'s body, between its opening brace and `sizes:`.
TIER_DURATION = re.compile(r"^\s*property int duration:\s*(.+)$", re.MULTILINE)
TIER_VELOCITY = re.compile(r"^\s*property int velocity:\s*(.+)$", re.MULTILINE)
# A per-member RANK, as it appears in an expression: an index, or a distance
# from some centre. Deliberately NOT "...multiplied by something": the first
# version of this required the rank to sit directly beside a `*`, and
# `Math.min(itemRoot.index, 10) * 50` - the exact cascade this file exists to
# have joined - slipped straight through it. A mention is enough, because a
# wait that depends on which member it belongs to IS a stagger.
RANKED = re.compile(r"\b(?:\w*[Ii]ndex|\w*[Dd]istance\w*)\b")
# Only a WAIT counts - a PauseAnimation's duration, or anything spelled as a
# delay. A NumberAnimation whose own LENGTH varies per member is a different
# technique (the weather widget desyncs its clouds by giving each a different
# drift duration) and has no rank ladder to terminate.
PAUSE_BLOCK = re.compile(r"\bPauseAnimation\s*\{")
DELAY_BINDING = re.compile(r"\bdelay\s*:\s*[^\n]*")


def animation_block() -> str:
    text = APPEARANCE.read_text(encoding="utf-8")
    start = text.index("    animation: QtObject {")
    end = text.index("\n    sizes: QtObject {")
    return text[start:end]


def qml_files():
    for path in sorted(ROOT.rglob("*.qml")):
        relative = path.relative_to(ROOT).as_posix()
        if relative.startswith("tests/"):
            continue
        yield relative, path


def test_the_policy_module_stays_pure():
    """A .pragma library has no engine context, so it may not reach for one."""
    text = POLICY.read_text(encoding="utf-8")
    body = "\n".join(line for line in text.splitlines()
                     if not line.lstrip().startswith("//"))
    assert body.lstrip().startswith(".pragma library"), \
        "motion_policy.js must be a .pragma library"
    for forbidden in ("Qt.", "Appearance.", "Config.", "Quickshell."):
        assert forbidden not in body, (
            f"motion_policy.js reaches {forbidden} - a .pragma library has no "
            f"engine context, and the point of the split is that the decisions "
            f"are reachable from a test. Pass it in as an argument.")


def test_every_catalogued_tier_is_scaled():
    block = animation_block()
    durations = TIER_DURATION.findall(block)
    assert len(durations) >= 12, \
        f"expected the whole tier catalogue, found {len(durations)} durations"
    for value in durations:
        assert value.startswith("motion.scale("), (
            f"a tier duration bypasses the multiplier: `{value.strip()}`. Eight "
            f"tiers state their base as a literal and four read it out of "
            f"animationCurves, so a scaling applied to one spelling and not the "
            f"other is the miss nobody sees in review.")

    velocities = TIER_VELOCITY.findall(block)
    assert velocities, "expected the tiers to still declare velocities"
    for value in velocities:
        assert value.startswith("motion.scaleVelocity("), (
            f"a tier velocity bypasses the multiplier: `{value.strip()}`. A "
            f"velocity is the reciprocal axis and needs its own scaling - "
            f"scaling it like a duration makes `slower` mean `faster`.")


def test_the_interaction_model_is_scaled_too():
    """The five-state model fires on every hover and press in the shell."""
    text = APPEARANCE.read_text(encoding="utf-8")
    start = text.index("readonly property var tiers: ({")
    tiers = text[start:text.index("})", start)]
    for name in ("hoverIn", "hoverOut", "press", "release"):
        entry = tiers[tiers.index(name + ":"):]
        entry = entry[:entry.index("}")]
        assert "motion.scale(" in entry, (
            f"the interaction model's `{name}` tier bypasses the multiplier. A "
            f"multiplier that slows every panel and leaves every button's press "
            f"acknowledging at a fixed duration is half a multiplier, and "
            f"reduce motion would miss the one class of motion that fires on "
            f"every interaction.")


def test_the_config_declares_both_keys_separately():
    text = CONFIG.read_text(encoding="utf-8")
    block = text[text.index("property JsonObject motion: JsonObject {"):]
    block = block[:block.index("\n                }")]
    assert re.search(r"property real multiplier:", block), \
        "appearance.motion.multiplier is not declared"
    assert re.search(r"property bool reduceMotion:", block), (
        "appearance.motion.reduceMotion is not declared. An undeclared key "
        "reads as `undefined` and takes the `??` fallback for ever, which "
        "would leave the reduce-motion state permanently off with nothing in "
        "any log.")


def test_the_speed_slider_cannot_reach_the_floor():
    """Accessibility is a switch, not the far end of a slider."""
    policy = POLICY.read_text(encoding="utf-8")
    minimum = float(re.search(r"var MULTIPLIER_MIN = ([\d.]+);", policy).group(1))
    maximum = float(re.search(r"var MULTIPLIER_MAX = ([\d.]+);", policy).group(1))
    assert minimum > 0, \
        "a multiplier range whose bottom is zero IS the reduce-motion floor"

    page = SETTINGS_PAGE.read_text(encoding="utf-8")
    row = page[page.index('text: Translation.tr("Animation speed")'):]
    row = row[:row.index("ConfigSwitch")]
    slider_from = float(re.search(r"\bfrom:\s*([\d.]+)", row).group(1))
    slider_to = float(re.search(r"\bto:\s*([\d.]+)", row).group(1))
    assert slider_from >= minimum, (
        f"the speed slider goes down to {slider_from}, below the policy's "
        f"clamp of {minimum}. The clamp would silently ignore the bottom of "
        f"the slider's own travel, so the control would lie about its range.")
    assert slider_to <= maximum, (
        f"the speed slider goes up to {slider_to}, above the policy's clamp "
        f"of {maximum}.")
    section = page[page.index('title: Translation.tr("Motion")'):]
    section = section[:section.index("ContentSection", 10)]
    switch = section[section.index("ConfigSwitch"):]
    assert "checked: Config.options.appearance.motion.reduceMotion" in switch, (
        "the Motion section offers no switch bound to the reduce-motion state, "
        "so an accessibility choice is reachable only by hand-editing "
        "config.json - or, worse, only by dragging the speed slider, which is "
        "the arrangement the separate key exists to prevent.")
    assert "onToggleRequested: Config.options.appearance.motion.reduceMotion" in switch, (
        "the reduce-motion switch does not write back through an intent. A "
        "ConfigSwitch that assigns to its own `checked` destroys the binding "
        "and then lies about the setting for the rest of the session (#158).")


def test_the_group_cascades_share_one_runner():
    wave = STAGGER_WAVE.read_text(encoding="utf-8")
    for call in ("Appearance.animation.staggerRanks(",
                 "Appearance.animation.staggerDelay(",
                 "Appearance.animation.scale("):
        assert call in wave, (
            f"StaggerWave no longer reaches {call}. It is the one runner every "
            f"container in this shell asks for a group entrance, so a clamp, a "
            f"rank or a scaling missing here is missing everywhere at once.")
    enter = wave[wave.index("function enter("):wave.index("function leave(")]
    assert ".visible" in enter, (
        "StaggerWave's rank list no longer consults `visible`, so the ranks it "
        "hands the policy are positions in `children` again - and a member "
        "that is not on screen leaves a hole one step wide in the wave.")

    assert "Appearance.animation.staggerDelay(" in CAROUSEL.read_text(encoding="utf-8"), (
        "Carousel no longer reaches the shared stagger policy. Its rank stays "
        "the model index because a delegate cannot see its siblings, but the "
        "clamp and the scaled step are still the policy's - which is the half "
        "that was wrong when the two cascades were separate.")


def test_nothing_else_ranks_its_own_wave():
    """One runner. A second is how the first two cascades came to disagree."""
    offenders = []
    for relative, path in qml_files():
        if relative == STAGGER_WAVE.relative_to(ROOT).as_posix():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        if "Appearance.animation.staggerRanks(" in text:
            offenders.append(relative)
    assert not offenders, (
        f"{offenders} rank a wave of their own. Ranking, clamping, scaling and "
        f"cancelling a group entrance live in StaggerWave - declare one and "
        f"call enter()/leave() instead of spelling a second copy, which is how "
        f"ExpandablePanel and Carousel came to disagree about both the clamp "
        f"and the step.")


def test_the_policy_has_one_door():
    """Only Appearance.qml imports the module; everything else asks Appearance."""
    importers = []
    for relative, path in qml_files():
        text = path.read_text(encoding="utf-8", errors="ignore")
        if re.search(r'^\s*import\s+"[^"]*motion_policy\.js"', text, re.MULTILINE):
            importers.append(relative)
    assert importers == ["modules/common/Appearance.qml"], (
        f"motion_policy.js is imported by {importers}. It takes the multiplier "
        f"and the reduce-motion flag as arguments, so a second importer is a "
        f"second place that has to resolve them from Config - which is how the "
        f"surveyed fork ended up with seven hand-copied thresholds.")


if __name__ == "__main__":
    sys.exit(run(globals()))
