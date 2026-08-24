#!/usr/bin/env python3
#
# Regression guard: the shared interaction model's hover/press motion is applied
# ONCE, by the control, and callers take what it gives them.
#
# `Item.scale` and a `Scale` transform COMPOSITE down the scene graph exactly the
# way `opacity` does, so a caller writing its own `scale: down ? a : (hovered ? b
# : 1)` inside a control that already applies `interactionMotion.scale` does not
# replace the model - it multiplies with it. `discordVoice`'s overlay shipped
# that on its mute and deafen glyphs: 1.02 x 1.08 on hover and 0.97 x 0.88 on
# press, roughly five times the intended excursion, on `OutBack` instead of the
# model's curve, and with one duration standing in for the five tiers
# `interaction_motion.js` exists to distinguish.
#
# This is `lint_disabled_opacity.py`'s rule with `scale` in place of `opacity`,
# and it is a separate file rather than a branch of that one because the two
# recognise different things: that lint keys on an `enabled`-conditioned dim
# expression and is blind to a transform, which is why the doubled scale sat
# beside a green suite for the whole life of the widget. A detector that knows
# one idiom stops detecting the moment the idiom changes.
#
# ...which is exactly how the FIRST version of this file missed the case its own
# commit message named. It knew one channel - `scale` - because the failure that
# motivated it was a transform, and it said so: "a file that merely declares one
# may be using only `pressProgress` for a radius, which composites with
# nothing." That sentence is about a transform's arithmetic and it left the
# radius channel with no rule at all, so `sessionScreen/SessionActionButton.qml`
# was written up in AGENT.md as found-and-not-fixed and the suite stayed green
# over it. A radius composites too, just through the control rather than through
# the scene graph: `RippleButton.buttonEffectiveRadius` is COMPUTED FROM
# `buttonRadius`, so a caller keying `buttonRadius` on `down` has its own value
# multiplied by `pressRadiusScale` on the way to the corner. Measured on the
# real component, a press took that button's corner from 30 to 51 - the button's
# jump to a circle, then the model's 0.85 landing on the circle - where every
# other control in the shell tightens.
#
# So the check is per CHANNEL now, and a channel is (the properties that express
# it, what applying the model in it looks like). A control is a control in the
# channels it actually applies the model in: `MediaTransportButton` scales and
# does not tighten, so a radius written inside it doubles nothing, and flagging
# it would be a rule nobody can act on.
#
# The rule: inside a control that applies the interaction model in a channel, no
# descendant (and not the control itself) may write that channel from a raw
# hover/press flag. The sanctioned channels are the driver's own outputs -
# `scale`, `radiusScale`, `hoverProgress`, `pressProgress` - which carry the
# right tier because `InteractionMotion.qml` writes the tier onto the animation
# BEFORE the target.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = ROOT / "modules"

# A property is written either as a plain binding (`scale: ...`) or as a
# declaration that something else then reads (`property real squish: ...`).
# Matching only the first leaves an indirection one rename wide open; matching
# both adds no hit to the current tree, so this closes a hole rather than moving
# the goalposts.
DECL_PREFIX = r"(?:readonly\s+)?(?:property\s+\w+\s+)?"


def prop_matcher(names):
    return re.compile(rf"^\s*{DECL_PREFIX}(?:{'|'.join(names)})\s*:(.*)$")


# The raw interaction flags a control exposes. Deliberately NOT `hoverProgress`
# or `pressProgress`: those are the model's own animated channels and reading
# them is the adoption this check wants, not the doubling it forbids.
STATE_FLAG = re.compile(
    r"\b(hovered|hoveredNow|hovering|down|pressed|isPressed|isHovered"
    r"|containsMouse|containsPress)\b"
)

# A file declares itself an interaction-model control by driving an
# `InteractionMotion` and applying one of its outputs. Both halves are required:
# a file that merely declares one is a driver nobody has wired up yet, and
# nothing inside it is doubling anything.
DRIVES_MOTION = re.compile(r"\bInteractionMotion\s*\{")

# The scale-family properties. A transform is a transform however it is spelled:
# `scale` on an Item, or `xScale`/`yScale` inside a `Scale {}`.
SCALE_NAMES = ("scale", "xScale", "yScale")

# The radius-family properties, plus the two per-corner vocabularies the two
# `RippleButton`s expose (`cornerTopLeft...` on the mainline one,
# `topLeftRadius...` on the design system's, which `SegmentedWrapper` drives).
#
# `buttonRadiusPressed` and `buttonEffectiveRadius` are deliberately absent from
# the OFFENDING set: the first is the model's own escape hatch - the value it
# interpolates TO, so naming it replaces the tightening instead of stacking on
# it - and the second is the applied result.
RADIUS_NAMES = (
    "radius", "buttonRadius",
    "topLeftRadius", "topRightRadius", "bottomLeftRadius", "bottomRightRadius",
    "cornerTopLeft", "cornerTopRight", "cornerBottomLeft", "cornerBottomRight",
)
RADIUS_APPLIER_NAMES = RADIUS_NAMES + ("buttonEffectiveRadius",)

# What "this file applies the model in this channel" looks like. Scale is read
# straight off the driver; a radius is a lerp along `pressProgress` (or a
# multiply by `radiusScale`), because a corner has no origin to scale about.
APPLIES_SCALE = re.compile(r"\.\s*scale\b")
APPLIES_RADIUS = re.compile(r"\.\s*(?:pressProgress|radiusScale)\b")

TYPE_BEFORE_BRACE = re.compile(r"([A-Z]\w*)\s*$")

# An expression continues onto the next line whenever it cannot stand alone yet:
# it ends on an operator, or the next line opens with one. Brackets are handled
# by depth instead - treating a leading `}` as a continuation swallows the line
# that CLOSES the enclosing object, which puts a sibling's text into this
# declaration's value.
CONTINUES = re.compile(r"(\?|:|\|\||&&|[-+*/,(\[]|\breturn\b)\s*$")
STARTS_CONTINUATION = re.compile(r"^\s*([?:.]|\|\||&&|[-+*/])")


def strip_noise(line):
    """Blank out string literals and line comments so brace counting is honest."""
    out = []
    quote = None
    index = 0
    while index < len(line):
        char = line[index]
        if quote:
            if char == "\\":
                out.append(" ")
                index += 2
                out.append(" ")
                continue
            out.append(" " if char != quote else char)
            if char == quote:
                quote = None
            index += 1
            continue
        if char in "\"'":
            quote = char
            out.append(char)
            index += 1
            continue
        if char == "/" and index + 1 < len(line) and line[index + 1] == "/":
            break
        out.append(char)
        index += 1
    return "".join(out)


def enclosing_types(lines):
    """Type-name stack in effect at each line, by brace depth.

    A `{` is attributed to the identifier immediately before it, so
    `contentItem: MaterialShapeWrappedMaterialSymbol {` pushes the type while
    `onClicked: {` and `function f() {` push nothing.
    """
    stack = []
    per_line = []
    for line in lines:
        per_line.append(tuple(name for name in stack if name))
        clean = strip_noise(line)
        for position, char in enumerate(clean):
            if char == "{":
                match = TYPE_BEFORE_BRACE.search(clean[:position])
                stack.append(match.group(1) if match else None)
            elif char == "}" and stack:
                stack.pop()
    return per_line


def declaration_value(lines, index, first_fragment):
    """The WHOLE right-hand side, not the line that opens it.

    A source-text check over a QML property has to answer whether the value is a
    line or a block - the settled-span check was vacuous for the largest tree it
    named because it read only the line, and `readonly property real spanW: {`
    says nothing at all. The radius channel needs it for a second reason: both
    `RippleButton`s declare `buttonEffectiveRadius` across two lines, with
    `pressProgress` on the continuation, so a line-scoped detector would not
    recognise either control.
    """
    value = strip_noise(first_fragment)
    depth = value.count("{") - value.count("}")
    depth += value.count("(") - value.count(")")
    depth += value.count("[") - value.count("]")
    cursor = index + 1
    while cursor < len(lines):
        stripped = value.strip()
        if depth <= 0 and not CONTINUES.search(stripped):
            nxt = strip_noise(lines[cursor])
            if not STARTS_CONTINUATION.match(nxt) or not nxt.strip():
                break
        nxt = strip_noise(lines[cursor])
        value += "\n" + nxt
        depth += nxt.count("{") - nxt.count("}")
        depth += nxt.count("(") - nxt.count(")")
        depth += nxt.count("[") - nxt.count("]")
        cursor += 1
    return value


# The group entrance's shared dressing writes the scale (and opacity) channel
# onto every `appear`-declaring member of its target, so a `StaggerEntrance`
# declared inside a control that applies the model is the same doubling with
# the writer one component away: the entrance scale composites with the
# control's `interactionMotion.scale` down the scene graph, and the opacity it
# installs multiplies with the dim the control's root already carries. (The
# component itself SKIPS a direct child owning an `interactionMotion`, but a
# dresser aimed at a container INSIDE the control reaches members that guard
# cannot see - the members are plain items, the control is their ancestor.)
DRESSER_TYPES = ("StaggerEntrance",)
DRESSER = re.compile(r"^\s*(" + "|".join(DRESSER_TYPES) + r")\s*\{")


class Channel:
    """One visual channel the model drives, and how to recognise both sides."""

    def __init__(self, name, offending, applier, applies, doubling,
                 dressers=False):
        self.name = name
        self.offending = prop_matcher(offending)
        self.applier = prop_matcher(applier)
        self.applies = applies
        self.doubling = doubling
        # Whether the shared entrance dressing writes this channel too. Scale
        # only: the dresser installs no radius.
        self.dressers = dressers


CHANNELS = [
    Channel(
        "scale", SCALE_NAMES, SCALE_NAMES, APPLIES_SCALE,
        "a transform composites down the scene graph, so a hover/press scale "
        "written inside a control that already applies `interactionMotion.scale` "
        "MULTIPLIES with the model instead of replacing it",
        dressers=True,
    ),
    Channel(
        "radius", RADIUS_NAMES, RADIUS_APPLIER_NAMES, APPLIES_RADIUS,
        "the control's pressed radius is COMPUTED FROM `buttonRadius`, so a "
        "hover/press radius written inside one is multiplied by "
        "`pressRadiusScale` on its way to the corner - two sources on one "
        "channel, which is how a session button ended up GROWING its corner on "
        "press while the rest of the shell tightens",
    ),
]


def motion_controls(sources, channel):
    """Files whose declaration applies the model in this channel."""
    found = set()
    for path, lines in sources.items():
        if not any(DRIVES_MOTION.search(line) for line in lines):
            continue
        for index, line in enumerate(lines):
            match = channel.applier.match(line)
            if not match:
                continue
            if channel.applies.search(declaration_value(lines, index, match.group(1))):
                found.add(path)
                break
    return found


def scan(sources, channel, controls):
    """(violations, files that opened a motion-control block for this channel)."""
    violations = []
    hosts = set()
    for path, lines in sources.items():
        stacks = enclosing_types(lines)
        own_type = path.stem
        for number, line in enumerate(lines, 1):
            enclosing = set(stacks[number - 1])
            if own_type in controls:
                enclosing.add(own_type)
            inside = enclosing & controls
            if inside:
                hosts.add(path)
            if channel.dressers and inside:
                dresser = DRESSER.match(line)
                if dresser:
                    violations.append((path, number, sorted(inside)[0],
                                       f"{dresser.group(1)} dresses members "
                                       f"with a scale of its own here"))
                    continue
            match = channel.offending.match(line)
            if not match or not inside:
                continue
            value = declaration_value(lines, number - 1, match.group(1))
            if STATE_FLAG.search(value):
                violations.append((path, number, sorted(inside)[0],
                                   " ".join(value.split())[:90]))
    return violations, hosts


# The check matches source text over a tree it does not control, so both halves
# of it are proven against a fixture that cannot drift: per channel, a doubling
# written as a plain ternary, one written as a block, one hidden behind a
# property declaration - and the spellings that must NOT redden, namely the
# driver's own outputs and anything outside a control. The radius fixture also
# carries the two-line `buttonEffectiveRadius` shape, because a line-scoped
# detector would silently find no radius control at all and report a clean tree.
SELF_CHECK = {
    "Control.qml": """
Button {
    property InteractionMotion interactionMotion: InteractionMotion {
        hovered: root.hovered
    }
    transform: Scale {
        xScale: root.interactionMotion.scale
        yScale: root.interactionMotion.scale
    }
}
""",
    "CallSite.qml": """
Item {
    Control {
        contentItem: Glyph {
            scale: parent?.down ? 0.88 : (parent?.hovered ? 1.08 : 1)
        }
        Label {
            scale: {
                if (parent.hovered)
                    return 1.2;
                return 1;
            }
        }
        Icon {
            scale: root.motion.scale
        }
        StaggerEntrance {
            target: glyphColumn
        }
    }
    Loose {
        scale: hoverArea.containsMouse ? 1.1 : 1
    }
    StaggerEntrance {
        target: looseColumn
    }
}
""",
    "Tightening.qml": """
Button {
    property InteractionMotion interactionMotion: InteractionMotion {
        down: root.down
    }
    property real buttonRadius: 8
    property real buttonRadiusPressed: buttonRadius * Appearance.interaction.pressRadiusScale
    property real buttonEffectiveRadius: root.buttonRadius
        + (root.buttonRadiusPressed - root.buttonRadius) * interactionMotion.pressProgress
    background: Rectangle {
        radius: root.buttonEffectiveRadius
    }
}
""",
    # Rooted ON the control, which is the shape that was missed: a
    # `RippleButton` subclass re-stating the press in its own radius.
    "TighteningCallSite.qml": """
Tightening {
    buttonRadius: (button.focus || button.down) ? size / 2 : Appearance.rounding.verylarge
    QtObject {
        property real radius: button.hovered ? 4 : 12
    }
    Rectangle {
        radius: {
            if (button.down)
                return 4;
            return 12;
        }
    }
    Rectangle {
        radius: root.someShape ? 4 : 12
    }
}
""",
    "TighteningLoose.qml": """
Item {
    Loose {
        radius: hoverArea.containsMouse ? 4 : 12
    }
}
""",
}


def self_check():
    sources = {Path(name): text.splitlines()
               for name, text in SELF_CHECK.items()}
    expected = {
        "scale": ({"Control"},
                  {("CallSite.qml", 5), ("CallSite.qml", 8),
                   ("CallSite.qml", 17)},
                  "CallSite.qml", None),
        "radius": ({"Tightening"},
                   {("TighteningCallSite.qml", 3), ("TighteningCallSite.qml", 5), ("TighteningCallSite.qml", 8)},
                   "TighteningCallSite.qml", "TighteningLoose.qml"),
    }
    for channel in CHANNELS:
        want_controls, want_hits, want_host, want_clean = expected[channel.name]
        controls = {path.stem for path in motion_controls(sources, channel)}
        if controls != want_controls:
            return (f"the {channel.name}-channel control detector resolved "
                    f"{controls or 'nothing'} on a fixture declaring "
                    f"{want_controls}")
        violations, hosts = scan(sources, channel, controls)
        found = {(path.name, number) for path, number, _, _ in violations}
        if found != want_hits:
            return (f"the {channel.name} scan resolved {sorted(found)} on a "
                    f"fixture holding doublings at {sorted(want_hits)}")
        if Path(want_host) not in hosts:
            return (f"the block parser did not see the {channel.name} control "
                    f"instantiated at {want_host}")
        if want_clean and Path(want_clean) in hosts:
            return (f"the {channel.name} scan placed {want_clean} inside a "
                    "control it never instantiates, so its rule reaches "
                    "further than the model does")
    return None


# Pin what each detector is supposed to have found, by FILE rather than by type
# name: the plugin design system ships its own `RippleButton`, so a name-level
# guard stays satisfied by the copy while the mainline one loses its transform -
# the state in which flagging inner scales is exactly wrong.
EXPECTED_CONTROLS = {
    "scale": {
        "common/widgets/RippleButton.qml",
        "common/plugins/designsystem/widgets/RippleButton.qml",
        "common/plugins/bundled/nandoroid-media/MediaTransportButton.qml",
    },
    # `MediaTransportButton` is absent on purpose: it scales and does not
    # tighten, so it is not a radius-channel control and a radius inside it
    # doubles nothing.
    "radius": {
        "common/widgets/RippleButton.qml",
        "common/plugins/designsystem/widgets/RippleButton.qml",
    },
}

# ...and pin that the nesting analysis resolves against the real tree, not only
# against the fixture. One file whose ROOT is a control, one that instantiates
# them as children - the two shapes the stack has to get right.
EXPECTED_HOSTS = {
    "scale": {
        "common/widgets/ConfigSwitch.qml",
        "common/plugins/bundled/discordVoice/Widget.qml",
    },
    "radius": {
        "common/widgets/ConfigSwitch.qml",
        "imi/sessionScreen/SessionActionButton.qml",
    },
}


def main():
    broken = self_check()
    if broken:
        print("Interaction-motion lint FAILED its own self-check: "
              f"{broken}. The check below cannot be trusted.", file=sys.stderr)
        return 1

    files = sorted(MODULES.rglob("*.qml"))
    sources = {path: path.read_text(encoding="utf-8").splitlines()
               for path in files}

    failed = False
    summary = []
    for channel in CHANNELS:
        control_files = motion_controls(sources, channel)
        controls = {path.stem for path in control_files}

        found_controls = {str(path.relative_to(MODULES)) for path in control_files}
        missing = EXPECTED_CONTROLS[channel.name] - found_controls
        if missing:
            print(f"Interaction-motion lint FAILED: the {channel.name}-channel "
                  f"scan found no applied interaction model in {sorted(missing)} "
                  "- either those controls stopped driving the model, or the "
                  "detector's shape assumption broke and every call site below "
                  "is now unguarded.", file=sys.stderr)
            return 1

        violations, hosts = scan(sources, channel, controls)

        found_hosts = {str(path.relative_to(MODULES)) for path in hosts}
        missing_hosts = EXPECTED_HOSTS[channel.name] - found_hosts
        if missing_hosts:
            print("Interaction-motion lint FAILED: the brace-depth scan no "
                  f"longer places anything inside a {channel.name}-channel "
                  f"control in {sorted(missing_hosts)}, so it would report a "
                  "clean tree whatever those files contain.", file=sys.stderr)
            return 1

        if violations:
            failed = True
            print(f"Interaction-motion lint FAILED in the {channel.name} "
                  f"channel: {channel.doubling} - and carries one hand-picked "
                  "duration where the model has five tiers. Delete it; the "
                  "control already drives the whole subtree:", file=sys.stderr)
            for path, number, control, value in violations:
                rel = path.relative_to(MODULES)
                print(f"  {rel}:{number}: inside {control}: {value}",
                      file=sys.stderr)
        summary.append(f"{len(control_files)} {channel.name} controls in "
                       f"{len(hosts)} files")

    if failed:
        return 1

    print(f"Interaction-motion lint passed ({len(files)} QML files, "
          + ", ".join(summary) + ")")
    return 0


if __name__ == "__main__":
    sys.exit(main())
