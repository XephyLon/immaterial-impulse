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
EDIT_MODE_DRAWER = ROOT / "modules/imi/editMode/EditModeDrawer.qml"

# Every container that staggers a group, as a RATCHET rather than a list: a new
# adopter is a line here, and an adopter that quietly stops staggering fails the
# suite instead of going quiet. The measured survey
# (docs/p3drovfx-motion-measured-2026-08-22.md §4.2) found the policy correct,
# the guideline written, and the wiring at three files against the sibling
# fork's twenty - so the thing that decays here is adoption, not the arithmetic,
# and adoption is what this pins.
STAGGER_ADOPTERS = {
    "modules/common/widgets/ExpandablePanel.qml",
    "modules/common/widgets/ContentPage.qml",
    "modules/imi/sessionScreen/SessionScreen.qml",
    "modules/imi/editMode/EditModeDrawer.qml",
    # The bar popups' shared card: the second adopter whose container has a
    # real progress to gate on (card.openProgress through
    # Appearance.animation.contentsArrived), so like the drawer it carries no
    # leadIn. One wave on the overlay, never one per popup - the per-popup
    # content files only opt their below-the-fold sections in with `appear`;
    # the hero section deliberately declares none, because the card opens at
    # the hero's own height precisely so it is legible on frame one.
    # tests/lint_bar_popup_overlay_static.py holds the gate's shape.
    "modules/imi/bar/BarPopupOverlay.qml",
    # The desktop menu's rows. Adopted on the drawer's argument, not the
    # sidebar's counter-argument: the card's own entrance is a QML-readable
    # scalar (its opacity Behavior), so the wave gates on the real container
    # progress with no guessed leadIn - the exact property whose absence
    # refused the right sidebar. Its rows are RippleButtons, so they ride the
    # wave through the `appear` the control already folds; the card enters via
    # scale/opacity itself, so only the rows cascade. Enter-only by
    # construction: the window is destroyed with the close, so there is no
    # exit for a wave to waste frames on (the sidebar's measured 13-frames-
    # per-close cost cannot arise), and the per-open surface build is a cost
    # the menu already paid before the wave.
    "modules/imi/desktopMenu/DesktopMenu.qml",
}

# The other half of that ratchet: a surface that adopted a wave, was judged on
# screen, and had it taken back off. Without this the register only ever grows -
# the next agent reads "a group arrives in sequence" in the guidelines, sees a
# column of independent cards, and re-adopts the one surface where that was
# tried and refused. A refusal is invisible in the source, exactly like the
# adoption it mirrors.
#
# The right sidebar is the entry. 9e10b8a9c ("feat(sidebar): the right
# sidebar's sections arrive in sequence") gave it one and the user rejected it:
# "I don't like the cascading animation effect in the sidebar... This one feels
# slow. There's a frame drop the moment it opens and the moment it closes."
# Two properties of THIS surface are why, and neither is a tuning. Its
# container is a layer surface the compositor slides, so there is no progress
# to gate on and the head start can only be a guessed `leadIn` - which put the
# last member's landing 180ms past the end of `sidebarSlideEnter`. And the
# surface is DESTROYED by the gesture the wave rides: `PanelWindow.visible`
# follows the open state, layer-shell forbids window reuse, so the wave's
# frames land on a surface the compositor is still bringing up and its exit
# animates a window that has already been asked to leave - measured at a median
# of 30 rendered frames per open against 5 without it, and 13 per close against
# zero. The frame drop the report names is that teardown-and-rebuild and NOT
# the wave; see AGENT.md's design-language section, which carries the numbers
# and the two suspects they eliminate. Re-adopting is a decision to be argued,
# not a line to be copied.
STAGGER_DECLINED = {
    "modules/imi/sidebarRight/SidebarRightContent.qml",
    # Dialog content. Assessed for the group entrance when the desktop menu
    # adopted it and refused on the surface's own facts, all of them readable
    # in the tree rather than guessed:
    #
    #  - A dialog's content is the question being asked. Every WindowDialog
    #    here is an interruption offering a decision (the polkit auth prompt,
    #    the uninstall confirm, the Wi-Fi/Bluetooth/Tailscale/volume/phone
    #    dialogs), and a clamped five-rank wave puts the last member's landing
    #    ~400ms after the gate - latency on exactly the thing the user was
    #    interrupted to read. This is the launcher refusal's argument on a
    #    modal surface: a wave is wrong where the content IS what is being
    #    waited for.
    #  - The polkit prompt `forceActiveFocus()`es its field the moment it
    #    opens (PolkitContent.qml) and users answer immediately; a cascade
    #    puts keystrokes into a password field still parked at `appear: 0`,
    #    invisible, on an authentication surface.
    #  - The card already has an entrance of its own that members would fight:
    #    `onShowChanged` freezes the card's height at the show flip (the
    #    binding-destroying assignment AGENT.md documents as load-bearing) and
    #    the card unfolds 0 -> that height while the content column fades AS
    #    ONE - a per-member cascade inside an unfolding card is two entrances
    #    stacked on one surface.
    #  - Six of the dialog content files bleed children to the card's edge
    #    with negative `contentPadding` margins (separators, lists); a
    #    scale-and-rise dressing on those members swings edge-to-edge chrome
    #    onto the scrim mid-entrance, and separators would spend wave slots.
    #  - The dialog surfaces are created by the gesture that opens them (the
    #    sidebar's `toggleDialogLoader.active` flips on `shown`;
    #    FullscreenPolkitWindow is gated on `PolkitService.active`), which is
    #    the measured half of the sidebar refusal above: wave frames landing
    #    on a surface the compositor is still bringing up.
    #
    # A dialog that someday earns a group entrance argues these down first -
    # in particular the first two, which are properties of what a dialog IS
    # rather than of how this one is built.
    "modules/common/widgets/WindowDialog.qml",
}

# A cascade whose rank is bounded by the shape of its own model rather than by
# a clamp, and whose step is deliberately tighter than a group entrance's. The
# lyric strip is a fixed five-slot window that ripples outward from the active
# line, so `Math.abs(distanceFromActive)` can only ever be 0, 1 or 2 - there is
# no long-list case to terminate, and folding it into the group-entrance policy
# would widen a deliberate 25ms ripple to a 40ms wave for no defect fixed.
STAGGER_EXEMPT = {
    "modules/common/plugins/designsystem/widgets/DesktopMediaWidget.qml",
}

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
    # The RANK LIST, not the whole of enter(): the deferral guard beside it
    # also reads `visible`, so a check scoped to the function passes on a
    # runner that has stopped ranking - planted and confirmed.
    ranking = wave[wave.index("const included = []"):wave.index("const ranks =")]
    assert ".visible" in ranking, (
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


def test_the_stagger_is_adopted_where_a_group_arrives():
    """A ratchet on adoption, because adoption is the thing that decayed.

    It runs in both directions: a surface that stops staggering reddens, and so
    does one that starts again after being refused. The second half exists
    because the first half only ever pushes one way - a register of adopters
    reads as a target, and the surface a user has already turned down is
    exactly the one a later sweep would put back.
    """
    declared = {relative for relative, path in qml_files()
                if "StaggerWave {" in path.read_text(encoding="utf-8", errors="ignore")}
    missing = STAGGER_ADOPTERS - declared
    assert not missing, (
        f"{sorted(missing)} no longer declare a StaggerWave. Each of these is a "
        f"surface whose members arrive as a GROUP; without one they arrive in a "
        f"single frame again, which is invisible in the source and reads on "
        f"screen as the shell being flat rather than as a bug.")

    # A file that moved or was renamed would empty the declined register
    # silently, and a register that sweeps nothing is greener than one that is
    # wrong.
    for relative in STAGGER_DECLINED:
        assert (ROOT / relative).is_file(), (
            f"{relative} is in STAGGER_DECLINED and is not on disk. Point the "
            f"entry at wherever the surface moved to, or drop it with the same "
            f"argument that put it there - a register naming nothing passes.")

    readopted = STAGGER_DECLINED & declared
    assert not readopted, (
        f"{sorted(readopted)} declare a StaggerWave again. Each of these had "
        f"one, was looked at on screen, and had it removed - see "
        f"STAGGER_DECLINED for the reasoning and AGENT.md's design-language "
        f"section for what it cost. Re-adopting needs that argument answered, "
        f"not a line copied from a sibling surface.")

    assert not STAGGER_ADOPTERS & STAGGER_DECLINED, (
        "a surface is in both registers, so one of the two checks above can "
        "never pass.")


def test_the_drawer_gates_its_wave_on_the_container_it_lands_in():
    """The one adopter whose container has a progress to gate on.

    Every other adopter's container is animated by something QML has no scalar
    for - a settings page cross-fade, a layer surface the compositor slides -
    so `StaggerWave.leadIn` stands in for the head start. Edit Mode's drawer
    reveal IS `GlobalStates.editDrawerProgress`, so it can ask the real
    question instead of guessing at a delay: the wave is not started until the
    container has actually arrived. Without the gate it races the reveal it is
    meant to land in, which is what makes a staggered group read as loose.
    """
    drawer = EDIT_MODE_DRAWER.read_text(encoding="utf-8")
    assert "Appearance.animation.contentsArrived(" in drawer, (
        "Edit Mode's drawer no longer gates its contents on the container's "
        "own progress.")
    assert not re.search(r"^\s*leadIn:", drawer, re.MULTILINE), (
        "the drawer's wave carries a lead-in as well as the gate. Two waits in "
        "front of one wave, and only one of them is answerable from the "
        "container's own motion.")


def test_nothing_else_computes_a_ranked_wait():
    offenders = []
    for relative, path in qml_files():
        if relative in STAGGER_EXEMPT:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        waits = []
        for match in PAUSE_BLOCK.finditer(text):
            brace = text.index("{", match.start())
            depth = 0
            for index in range(brace, len(text)):
                if text[index] == "{":
                    depth += 1
                elif text[index] == "}":
                    depth -= 1
                    if depth == 0:
                        break
            waits.append((match.start(), text[brace:index + 1]))
        for match in DELAY_BINDING.finditer(text):
            waits.append((match.start(), match.group(0)))

        for position, wait in waits:
            if not RANKED.search(wait):
                continue
            if "Appearance.animation.staggerDelay(" in wait:
                continue
            line = text.count("\n", 0, position) + 1
            offenders.append(f"{relative}:{line}: {' '.join(wait.split())}")
    assert not offenders, (
        "a cascade computes its own delay instead of asking the policy:\n  "
        + "\n  ".join(offenders)
        + "\nUse Appearance.animation.staggerDelay(rank, step, leadIn) - it "
          "clamps the rank, which `index * step` does not, and it collapses "
          "at the reduce-motion floor without a second gate.")


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
