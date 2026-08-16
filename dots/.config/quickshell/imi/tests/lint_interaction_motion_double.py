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
# The rule: inside a control that applies the interaction model's `scale`, no
# descendant (and not the control itself) may write a scale-family property from
# a raw hover/press flag. The sanctioned channels are the driver's own outputs -
# `scale`, `hoverProgress`, `pressProgress` - which carry the right tier because
# `InteractionMotion.qml` writes the tier onto the animation BEFORE the target.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = ROOT / "modules"

# The scale-family properties. A transform is a transform however it is spelled:
# `scale` on an Item, or `xScale`/`yScale` inside a `Scale {}`.
SCALE_PROP = re.compile(r"^\s*(scale|xScale|yScale)\s*:(.*)$")

# The raw interaction flags a control exposes. Deliberately NOT `hoverProgress`
# or `pressProgress`: those are the model's own animated channels and reading
# them is the adoption this check wants, not the doubling it forbids.
STATE_FLAG = re.compile(
    r"\b(hovered|hoveredNow|hovering|down|pressed|isPressed|isHovered"
    r"|containsMouse|containsPress)\b"
)

# A file declares itself an interaction-model control by driving an
# `InteractionMotion` and applying its `scale`. Both halves are required: a file
# that merely declares one may be using only `pressProgress` for a radius, which
# composites with nothing.
DRIVES_MOTION = re.compile(r"\bInteractionMotion\s*\{")
APPLIES_MOTION_SCALE = re.compile(
    r"^\s*(?:scale|xScale|yScale)\s*:.*\.\s*scale\b"
)

TYPE_BEFORE_BRACE = re.compile(r"([A-Z]\w*)\s*$")

# An expression continues onto the next line whenever it cannot stand alone yet.
CONTINUES = re.compile(r"(\?|:|\|\||&&|[-+*/,(\[]|\breturn\b)\s*$")
STARTS_CONTINUATION = re.compile(r"^\s*([?:.]|\|\||&&|[-+*/)\]}])")


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
    says nothing at all.
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


def motion_controls(sources):
    """Type names (file stems) whose declaration applies the model's scale."""
    return {
        path
        for path, lines in sources.items()
        if any(DRIVES_MOTION.search(line) for line in lines)
        and any(APPLIES_MOTION_SCALE.match(line) for line in lines)
    }


def scan(sources, controls):
    """(violations, files that opened a motion-control block)."""
    violations = []
    hosts = set()
    for path, lines in sources.items():
        stacks = enclosing_types(lines)
        own_type = path.stem
        for number, line in enumerate(lines, 1):
            enclosing = set(stacks[number - 1])
            if path.stem in controls:
                enclosing.add(own_type)
            inside = enclosing & controls
            if inside:
                hosts.add(path)
            match = SCALE_PROP.match(line)
            if not match or not inside:
                continue
            value = declaration_value(lines, number - 1, match.group(2))
            if STATE_FLAG.search(value):
                violations.append((path, number, sorted(inside)[0],
                                   " ".join(value.split())[:90]))
    return violations, hosts


# The check matches source text over a tree it does not control, so both halves
# of it are proven against a fixture that cannot drift: a doubled scale written
# as a plain ternary, one written as a block, and the two spellings that must
# NOT redden - the driver's own output, and a scale outside any control.
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
    }
    Loose {
        scale: hoverArea.containsMouse ? 1.1 : 1
    }
}
""",
}


def self_check():
    sources = {Path(name): text.splitlines()
               for name, text in SELF_CHECK.items()}
    controls = {path.stem for path in motion_controls(sources)}
    if controls != {"Control"}:
        return (f"the interaction-model control detector resolved {controls or 'nothing'} "
                "on a fixture declaring exactly one")
    violations, hosts = scan(sources, controls)
    found = {(path.name, number) for path, number, _, _ in violations}
    if found != {("CallSite.qml", 5), ("CallSite.qml", 8)}:
        return (f"the scan resolved {sorted(found)} on a fixture holding a "
                "ternary doubling at 5 and a block doubling at 8")
    if Path("CallSite.qml") not in hosts:
        return "the block parser did not see the control instantiated at the call site"
    return None


def main():
    broken = self_check()
    if broken:
        print("Interaction-motion lint FAILED its own self-check: "
              f"{broken}. The check below cannot be trusted.", file=sys.stderr)
        return 1

    files = sorted(MODULES.rglob("*.qml"))
    sources = {path: path.read_text(encoding="utf-8").splitlines()
               for path in files}

    control_files = motion_controls(sources)
    controls = {path.stem for path in control_files}

    # Pin what the detector is supposed to have found, by FILE rather than by
    # type name: the plugin design system ships its own `RippleButton`, so a
    # name-level guard stays satisfied by the copy while the mainline one loses
    # its transform - the state in which flagging inner scales is exactly wrong.
    expected_controls = {
        "common/widgets/RippleButton.qml",
        "common/plugins/designsystem/widgets/RippleButton.qml",
        "common/plugins/bundled/nandoroid-media/MediaTransportButton.qml",
    }
    found_controls = {str(path.relative_to(MODULES)) for path in control_files}
    missing = expected_controls - found_controls
    if missing:
        print("Interaction-motion lint FAILED: the scan found no applied "
              f"`interactionMotion.scale` in {sorted(missing)} - either those "
              "controls stopped driving the model, or the detector's shape "
              "assumption broke and every call site below is now unguarded.",
              file=sys.stderr)
        return 1

    violations, hosts = scan(sources, controls)

    # ...and pin that the nesting analysis resolves against the real tree, not
    # only against the fixture. One file whose ROOT is a control, one that
    # instantiates them as children - the two shapes the stack has to get right.
    expected_hosts = {
        "common/widgets/ConfigSwitch.qml",
        "common/plugins/bundled/discordVoice/Widget.qml",
    }
    found_hosts = {str(path.relative_to(MODULES)) for path in hosts}
    missing_hosts = expected_hosts - found_hosts
    if missing_hosts:
        print("Interaction-motion lint FAILED: the brace-depth scan no longer "
              f"places anything inside a control in {sorted(missing_hosts)}, so "
              "it would report a clean tree whatever those files contain.",
              file=sys.stderr)
        return 1

    if violations:
        print("Interaction-motion lint FAILED: a transform composites, so a "
              "hover/press scale written inside a control that already applies "
              "`interactionMotion.scale` MULTIPLIES with the model instead of "
              "replacing it - and carries one hand-picked duration where the "
              "model has five tiers. Delete it; the control already scales the "
              "whole subtree:", file=sys.stderr)
        for path, number, control, value in violations:
            rel = path.relative_to(MODULES)
            print(f"  {rel}:{number}: inside {control}: {value}", file=sys.stderr)
        return 1

    print(f"Interaction-motion lint passed ({len(files)} QML files, "
          f"{len(controls)} interaction-model controls, "
          f"{len(hosts)} files hosting one)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
