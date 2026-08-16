#!/usr/bin/env python3
#
# Regression guard: an `Appearance.*` token a QML file reads must be declared in
# `modules/common/Appearance.qml`.
#
# `Appearance.rounding.button`, `.card` and `.extraLarge` were read by six call
# sites in the vendored design system from the day it was ported and were never
# declared. Nothing in this repo could see it, because the failure renders
# something plausible:
#
#   - An undeclared read is a plain `undefined` property read on a QtObject, not
#     an error. `radius: undefined` costs exactly one `Unable to assign
#     [undefined] to double` at binding evaluation - once, when the component is
#     first built, among the shell's ordinary reload noise - and then renders 0.
#     A square corner on a card that should be round looks like a design choice.
#   - Worse, a call site that does ARITHMETIC on the token gets NaN, which is a
#     legal double. Nothing rejects it at the assignment boundary, nothing logs
#     it, and it survives every arithmetic downstream. `Carousel.qml` computed
#     its mask radius that way. Measured: `undefined` produces one warning line,
#     the NaN form produces none at all.
#   - `run_tests.sh`'s QML suite instantiates pure-logic singletons and
#     `DesignSystemCompile.qml` only *compiles* components, and a binding is not
#     evaluated by either - so both stay green.
#
# This is the same family as the two undeclared-key failures AGENT.md already
# records: the pixel clock's `Config.options.background.widgets.enableShadows`
# gate that took its `??` fallback for ever, and the `activeStill` field with no
# writer. A name that is never declared reads as `undefined` everywhere, and
# `undefined` is a value rather than an error.
#
# What it does NOT fail on, deliberately:
#
#   - A dynamically-built member (`Appearance.rounding[rName]`,
#     `Appearance.colors["col" + name]`). The group itself is still resolved -
#     `Appearance.notAGroup[x]` fails - but the member cannot be known
#     statically, so those are COUNTED AND REPORTED rather than guessed at.
#   - Anything past a leaf. `Appearance.animation.elementMove.numberAnimation`
#     is a `Component`, so `.createObject(this)` after it is Qt's API and none of
#     this check's business. Resolution stops at the first property that is not
#     itself a `QtObject` group.
#   - Tokens on any other singleton. Only a bareword `Appearance.` chain is
#     resolved; `ExpressiveTokens.shape.card`, a local `appearance` variable or a
#     plugin manifest's own vocabulary are all out of scope.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPEARANCE = ROOT / "modules" / "common" / "Appearance.qml"

# A reference is `Appearance` followed by one or more `.name` hops, with QML's
# optional-chaining `?.` allowed at every hop (`Appearance?.rounding?.small` is
# written that way in the mainline RippleButton). A trailing `[` marks the point
# where the chain stops being resolvable.
REFERENCE = re.compile(
    r"\bAppearance\b((?:\s*\??\s*\.\s*[A-Za-z_]\w*)+)\s*(\[)?"
)
SEGMENT = re.compile(r"[A-Za-z_]\w*")

# A declaration at the top of an object body. The type may be generic
# (`list<real>`), the value may be absent (`property QtObject rounding`) or may
# open a group on the same line (`property QtObject elementMove: QtObject {`).
DECLARATION = re.compile(
    r"^\s*(?:readonly\s+)?property\s+\w+(?:\s*<[^>]*>)?\s+(\w+)\s*(?::\s*(.*))?$"
)
# A group assigned to a previously-declared property (`rounding: QtObject {`).
ASSIGNMENT = re.compile(r"^\s*(\w+)\s*:\s*(.*)$")
# The rest of what the port left behind, quarantined rather than swallowed.
#
# The rounding tokens were three of FIFTEEN names the nandoroid port brought
# call sites for and never brought declarations for; this check found the other
# twelve on its first run. They are not fixed here because each one is the same
# piece of work the rounding tokens were - a value decision against
# docs/M3_GUIDELINES.md and the surrounding call sites - and a number chosen to
# silence a check renders a wrong shape or a wrong colour that then reads as
# deliberate. That is a worse outcome than the bug.
#
# Every one of them is in a design-system component that nothing in this shell
# instantiates (`ComponentRegistry` catalogues 107, a reachability closure from
# the live tree reaches 17, and none of these is among them), so none is on
# screen today. The moment one is adopted it is a 0, a NaN or a transparent
# colour.
#
# This list is a debt register, not an allowlist: a name that is NOT here fails
# the suite, and a name here that has SINCE been declared also fails it, so it
# cannot quietly outlive the debt.
QUARANTINE = {
    # M3 has no "warning" colour role and this shell has only error roles, so
    # mapping these is a semantic decision, not a rename.
    "colors.colWarning",
    "colors.colOnWarning",
    "colors.colWarningContainer",
    "colors.colOnWarningContainer",
    "colors.colStatusBarText",
    "colors.colStatusBarSubtext",
    "colors.colLockscreenClock",
    "colors.colLockscreenDate",
    "sizes.calendarSpacing",
    "sizes.contextMenuWidth",
    "sizes.contextMenuItemHeight",
    "sizes.iconSize",
}

# A member can also be a function. `Appearance.sizes.widgetGridSpanX(cols)` and
# `Appearance.interaction.state({...})` are both real members reached this way,
# and a parser that knows only `property` reports 40 clean call sites as
# undeclared - which is how a check gets loosened into uselessness.
FUNCTION = re.compile(r"^\s*function\s+(\w+)\s*\(")


def strip_noise(text: str) -> str:
    """Removes comments and string bodies, preserving line structure.

    Both matter. A comment naming a token is prose, not a read - this file's own
    header names three - and counting one would make the sweep report a
    reference the engine never evaluates. String bodies are removed so a brace
    or a quote inside one cannot desynchronise the depth tracking below.
    """
    out = []
    i = 0
    length = len(text)
    while i < length:
        char = text[i]
        if char == "/" and i + 1 < length and text[i + 1] == "/":
            while i < length and text[i] != "\n":
                i += 1
        elif char == "/" and i + 1 < length and text[i + 1] == "*":
            i += 2
            while i + 1 < length and not (text[i] == "*" and text[i + 1] == "/"):
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            i = min(i + 2, length)
        elif char in "\"'`":
            quote = char
            out.append(" ")
            i += 1
            while i < length and text[i] != quote:
                if text[i] == "\\":
                    i += 1
                out.append("\n" if i < length and text[i] == "\n" else " ")
                i += 1
            i += 1
            out.append(" ")
        else:
            out.append(char)
            i += 1
    return "".join(out)


def _matching_brace(text: str, open_index: int) -> int:
    depth = 0
    for index in range(open_index, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return len(text) - 1


def parse_body(body: str) -> dict:
    """Returns {name: children-or-None} for one object body's OWN properties.

    Only declarations at the body's top level count. `Appearance.qml` declares a
    `ColorQuantizer` with its own `property string wallpaperPath` inside it, and
    that is the quantizer's property rather than Appearance's - reading it as
    Appearance's would let a genuinely undeclared token resolve.
    """
    declared: dict = {}
    depth = 0
    for line in body.split("\n"):
        if depth == 1:
            function = FUNCTION.match(line)
            if function:
                declared.setdefault(function.group(1), None)
                depth += line.count("{") - line.count("}")
                continue
            match = DECLARATION.match(line)
            name = None
            value = None
            if match:
                name, value = match.group(1), (match.group(2) or "")
            else:
                match = ASSIGNMENT.match(line)
                if match and not line.lstrip().startswith("//"):
                    name, value = match.group(1), match.group(2)
            if name is not None:
                if name not in declared or declared[name] is None:
                    declared[name] = None
                if re.match(r"^QtObject\s*\{", value.strip()):
                    declared[name] = "pending"
        depth += line.count("{") - line.count("}")

    # Second pass for the group bodies, which need character offsets rather than
    # line offsets to find their matching brace.
    for match in re.finditer(r"(?:property\s+\w+\s+)?(\w+)\s*:\s*QtObject\s*\{", body):
        name = match.group(1)
        if declared.get(name) != "pending":
            continue
        open_index = body.index("{", match.end() - 1)
        close_index = _matching_brace(body, open_index)
        declared[name] = parse_body(body[open_index : close_index + 1])
    for name, value in declared.items():
        if value == "pending":
            declared[name] = {}
    return declared


def parse_appearance(text: str) -> dict:
    body = strip_noise(text)
    match = re.search(r"\bSingleton\s*\{", body)
    if not match:
        return {}
    open_index = body.index("{", match.end() - 1)
    close_index = _matching_brace(body, open_index)
    return parse_body(body[open_index : close_index + 1])


def scan(declared: dict, files, quarantine=frozenset()):
    """Returns (references, undeclared, dynamic, quarantined).

    A reference is (path, line, chain, resolved-depth); an undeclared entry is
    (path, line, chain, first-missing-segment). `quarantined` is the set of
    QUARANTINE keys the sweep actually saw, which is what lets a stale entry be
    reported rather than lingering.
    """
    references = []
    undeclared = []
    dynamic = []
    quarantined = set()

    for path in sorted(files):
        try:
            text = strip_noise(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError):
            continue

        for number, line in enumerate(text.split("\n"), start=1):
            for match in REFERENCE.finditer(line):
                segments = SEGMENT.findall(match.group(1))
                is_dynamic = match.group(2) is not None
                chain = "Appearance." + ".".join(segments)
                references.append((path, number, chain, len(segments)))

                node = declared
                missing = None
                key = None
                for index, segment in enumerate(segments):
                    if not isinstance(node, dict):
                        # Reached a leaf; everything past it is Qt/JS API.
                        break
                    if segment not in node:
                        missing = segment
                        key = ".".join(segments[: index + 1])
                        break
                    node = node[segment]
                    if node is not None and not node:
                        # A declared group whose body is empty behaves as a leaf.
                        node = None

                if missing is not None:
                    if key in quarantine:
                        quarantined.add(key)
                    else:
                        undeclared.append((path, number, chain, missing))
                elif is_dynamic:
                    dynamic.append((path, number, chain))

    return references, undeclared, dynamic, quarantined


def self_check() -> bool:
    """Proves the parser and the sweep both work, without the real tree.

    A source-text check that has quietly stopped matching passes vacuously, and
    a sweep over a tree that happens to be clean cannot tell you which of the
    two it is. The fixture carries a nested group, a leaf reached through a
    group, a chain continuing past a leaf into Qt's API, optional chaining, a
    dynamic member, a foreign singleton, a property belonging to a nested object
    rather than to Appearance, and a token named only in a comment - each of
    which this has to get right in a different direction.
    """
    appearance = """
pragma Singleton
import QtQuick
Singleton {
    id: root
    readonly property real effectiveScale: 1.0
    property QtObject rounding
    property QtObject animation

    ColorQuantizer {
        id: quant
        property string wallpaperPath: ""
    }

    rounding: QtObject {
        property int small: 12
        property int normal: 17
        property int card: normal
        function nested(cols) {
            return cols * 12;
        }
    }

    animation: QtObject {
        property QtObject elementMove: QtObject {
            property int duration: 400
            property Component numberAnimation: Component {
                NumberAnimation { duration: 400 }
            }
        }
    }
}
"""
    consumer = """
import qs.modules.common
Item {
    property int a: Appearance.rounding.card
    property int b: Appearance.rounding.normal
    property int c: Appearance?.rounding?.small ?? 4
    property int d: Appearance.animation.elementMove.duration
    property real e: Appearance.effectiveScale
    property var f: Appearance.animation.elementMove.numberAnimation.createObject(this)
    property int g: Appearance.rounding[dynamicName]
    property int h: ExpressiveTokens.shape.button
    property string i: Appearance.wallpaperPath
    // Appearance.rounding.commentOnly is prose, not a read
    property int j: Appearance.rounding.button
    property int k: Appearance.typography.body
    property int l: Appearance.rounding.nested(2)
}
"""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "modules" / "common").mkdir(parents=True)
        (root / "modules" / "common" / "Appearance.qml").write_text(appearance)
        (root / "modules" / "common" / "Consumer.qml").write_text(consumer)

        declared = parse_appearance(appearance)
        problems = []
        if set(declared.get("rounding") or {}) != {"small", "normal", "card", "nested"}:
            problems.append(f"rounding parsed as {sorted(declared.get('rounding') or {})}")
        if "duration" not in ((declared.get("animation") or {}).get("elementMove") or {}):
            problems.append("nested group animation.elementMove.duration not parsed")
        if "wallpaperPath" in declared:
            problems.append("a nested object's property leaked into Appearance's own")

        consumers = [root / "modules" / "common" / "Consumer.qml"]
        _, undeclared, dynamic, _ = scan(declared, consumers)
        missing = {chain for _, _, chain, _ in undeclared}
        if missing != {"Appearance.wallpaperPath",
                       "Appearance.rounding.button",
                       "Appearance.typography.body"}:
            problems.append(f"wrong undeclared set: {sorted(missing)}")
        if len(dynamic) != 1:
            problems.append(f"expected 1 dynamic reference, saw {len(dynamic)}")

        # The quarantine both suppresses and is itself checked: a quarantined
        # name must drop out of the failures AND be reported as seen, or a stale
        # entry could never be told apart from a live one. A key is the path up
        # to and including the FIRST segment that does not resolve - so an
        # unknown group is quarantined as `typography`, not `typography.body`;
        # there is no leaf to name under a group that does not exist.
        _, held, _, seen = scan(declared, consumers, {"rounding.button", "typography"})
        if {chain for _, _, chain, _ in held} != {"Appearance.wallpaperPath"}:
            problems.append(
                f"quarantine did not suppress: {sorted(c for _, _, c, _ in held)}"
            )
        if seen != {"rounding.button", "typography"}:
            problems.append(f"quarantine hits not reported back: {sorted(seen)}")
        _, _, _, seen_stale = scan(declared, consumers, {"rounding.small"})
        if seen_stale:
            problems.append("a quarantined name that resolves was counted as seen")

        if problems:
            print(
                "Appearance-token lint FAILED its own self-check, so it can say "
                "nothing about the tree:",
                file=sys.stderr,
            )
            for problem in problems:
                print(f"  {problem}", file=sys.stderr)
            return False
    return True


def main() -> int:
    if not self_check():
        return 1

    if not APPEARANCE.is_file():
        print(f"Appearance-token lint FAILED: {APPEARANCE} is missing.", file=sys.stderr)
        return 1

    declared = parse_appearance(APPEARANCE.read_text(encoding="utf-8"))
    if not declared:
        print(
            "Appearance-token lint FAILED: parsed no declarations out of "
            "Appearance.qml, so every reference in the shell would resolve to "
            "nothing. The parser broke, not the tree.",
            file=sys.stderr,
        )
        return 1

    files = [
        path
        for pattern in ("*.qml", "*.js")
        for path in ROOT.rglob(pattern)
        if ".git" not in path.parts
    ]
    references, undeclared, dynamic, quarantined = scan(declared, files, QUARANTINE)

    if not references:
        print(
            "Appearance-token lint FAILED: the sweep resolved no Appearance "
            "reference at all. Either nothing reads a design token any more - "
            "in which case this is guarding nothing - or the pattern broke.",
            file=sys.stderr,
        )
        return 1

    if undeclared:
        print(
            "Appearance-token lint FAILED: a QML file reads an Appearance token "
            "that Appearance.qml does not declare. An undeclared read is "
            "`undefined`, not an error: `radius: undefined` renders 0 after one "
            "`Unable to assign [undefined] to double`, and arithmetic on it "
            "yields NaN with no warning at all. Declare the token or stop "
            "naming it:",
            file=sys.stderr,
        )
        for path, number, chain, missing in undeclared:
            rel = path.relative_to(ROOT)
            print(f"  {rel}:{number}: {chain} (no `{missing}`)", file=sys.stderr)
        print(
            "\n(If this is one of the design-system port's remaining omissions, "
            "it belongs in QUARANTINE with a value decision behind it, not "
            "silenced with the first plausible number.)",
            file=sys.stderr,
        )
        return 1

    stale = sorted(QUARANTINE - quarantined)
    if stale:
        print(
            "Appearance-token lint FAILED: a name in QUARANTINE no longer "
            "resolves to nothing - it has either been declared or lost its last "
            "call site. The register is meant to shrink; drop these entries so "
            "it keeps meaning what it says:",
            file=sys.stderr,
        )
        for name in stale:
            print(f"  Appearance.{name}", file=sys.stderr)
        return 1

    print(
        f"Appearance-token lint passed ({len(references)} token references in "
        f"{len(files)} QML/JS files, {len(dynamic)} built dynamically and left "
        f"to their own call sites, {len(quarantined)} quarantined design-system "
        "omissions still outstanding)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
