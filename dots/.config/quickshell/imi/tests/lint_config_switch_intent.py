#!/usr/bin/env python3
#
# Regression guard: a ConfigSwitch click is an INTENT, never a write to
# `checked`.
#
# `ConfigSwitch.qml` used to answer its own click with `checked = !checked`,
# and every settings page binds that same property:
#
#     ConfigSwitch {
#         checked: Config.options.x.y
#         onCheckedChanged: Config.options.x.y = checked
#     }
#
# An imperative assignment to a bound property destroys the binding. From the
# first click onward the switch showed local state - no preset, hand-edited
# config or migration could move it again - while the row's write-back kept
# working, so the setting changed and the switch lied about it. The next click
# on a switch that looked on then wrote `!off` = on. 159 call sites had it
# (#158), and every one of them looked correct in isolation, which is why this
# is a check rather than a note: the idiom comes back one switch at a time.
#
# The shape that works keeps `checked` a pure binding and expresses the click
# as `toggleRequested()`, which the call site answers by flipping the value at
# its source:
#
#     ConfigSwitch {
#         checked: Config.options.x.y
#         onToggleRequested: Config.options.x.y = !Config.options.x.y
#     }
#
# So, enforced here:
#   1. ConfigSwitch.qml assigns to `checked` nowhere, declares
#      `signal toggleRequested()`, and raises it from `onClicked`.
#   2. Its inner StyledSwitch is `checkable: false`. A QQC2 Switch moves its own
#      `checked` on a click or a thumb drag, which would show a flip the call
#      site may decline and leave it wrong until the config next changed.
#   3. No ConfigSwitch call site assigns to `checked`, drives it through a
#      `Binding` object, or takes the write-back on `onCheckedChanged` /
#      overrides `onClicked` (which would swallow the intent).
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = ROOT / "modules"
WIDGET = MODULES / "common/widgets/ConfigSwitch.qml"

# The number of call sites when this check landed. It is a floor, not a pin:
# the point is that a reformat or a parser slip cannot leave the scan matching
# nothing while still reporting success.
MINIMUM_CALL_SITES = 150

ASSIGNS_CHECKED = re.compile(r"\bchecked\s*=(?![=~])")


def mask(source):
    """Blank out comments and string literals so braces inside them don't count."""
    out = list(source)
    i, n = 0, len(source)
    while i < n:
        char = source[i]
        if char == "/" and source[i + 1:i + 2] == "/":
            end = source.find("\n", i)
            end = n if end < 0 else end
        elif char == "/" and source[i + 1:i + 2] == "*":
            end = source.find("*/", i + 2)
            end = n if end < 0 else end + 2
        elif char in "\"'`":
            end = i + 1
            while end < n:
                if source[end] == "\\":
                    end += 2
                    continue
                if source[end] == char:
                    end += 1
                    break
                end += 1
        else:
            i += 1
            continue
        for position in range(i, min(end, n)):
            out[position] = " "
        i = end
    return "".join(out)


def blocks(masked):
    """(start, end) of every `ConfigSwitch { ... }` in a masked source."""
    found = []
    for match in re.finditer(r"\bConfigSwitch\s*\{", masked):
        depth, index = 0, match.end() - 1
        while index < len(masked):
            if masked[index] == "{":
                depth += 1
            elif masked[index] == "}":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        found.append((match.start(), index + 1))
    return found


def top_level_members(masked, start, end):
    """Property/handler names bound directly on the block, not on a child."""
    body_start = masked.index("{", start) + 1
    body_end = end - 1
    names = {}
    for match in re.finditer(r"[A-Za-z_][A-Za-z0-9_.]*\s*:", masked[body_start:body_end]):
        position = body_start + match.start()
        nested = (masked.count("{", body_start, position) - masked.count("}", body_start, position)
                  or masked.count("[", body_start, position) - masked.count("]", body_start, position)
                  or masked.count("(", body_start, position) - masked.count(")", body_start, position))
        if nested:
            continue
        names.setdefault(match.group()[:-1].strip(), masked[:position].count("\n") + 1)
    return names


def check_the_widget(violations):
    source = WIDGET.read_text(encoding="utf-8")
    masked = mask(source)
    if ASSIGNS_CHECKED.search(masked):
        line = masked[:ASSIGNS_CHECKED.search(masked).start()].count("\n") + 1
        violations.append((WIDGET.name, line,
                           "ConfigSwitch assigns to `checked`, which destroys "
                           "the call site's binding on the first click"))
    if not re.search(r"^\s*signal\s+toggleRequested\s*\(\s*\)", source, re.M):
        violations.append((WIDGET.name, 0,
                           "ConfigSwitch no longer declares `signal toggleRequested()`"))
    if not re.search(r"^\s*onClicked:\s*root\.toggleRequested\(\)", source, re.M):
        violations.append((WIDGET.name, 0,
                           "ConfigSwitch's click no longer raises toggleRequested()"))
    if not re.search(r"^\s*checkable:\s*false", source, re.M):
        violations.append((WIDGET.name, 0,
                           "the inner StyledSwitch is checkable again, so it "
                           "moves its own `checked` on click and drag"))


def main():
    if not WIDGET.exists():
        print(f"ConfigSwitch intent lint FAILED: {WIDGET} is missing - this "
              "check no longer guards anything.", file=sys.stderr)
        return 1

    violations = []
    check_the_widget(violations)

    call_sites = 0
    for path in sorted(MODULES.rglob("*.qml")):
        source = path.read_text(encoding="utf-8")
        if "ConfigSwitch" not in source:
            continue
        masked = mask(source)
        for start, end in blocks(masked):
            call_sites += 1
            relative = path.relative_to(MODULES)
            line = masked[:start].count("\n") + 1
            body = masked[start:end]
            members = top_level_members(masked, start, end)
            if ASSIGNS_CHECKED.search(body):
                violations.append((relative, line,
                                   "assigns to `checked` - that is the binding "
                                   "destroyed by hand"))
            if re.search(r'property:\s*"checked"', body):
                violations.append((relative, line,
                                   "drives `checked` through a Binding object - "
                                   "a plain `checked:` binding survives a click now"))
            if "onCheckedChanged" in members:
                violations.append((relative, members["onCheckedChanged"],
                                   "writes back from onCheckedChanged - `checked` "
                                   "no longer moves on a click, so this is a dead "
                                   "switch. Use onToggleRequested"))
            if "onClicked" in members:
                violations.append((relative, members["onClicked"],
                                   "overrides onClicked, which is where the base "
                                   "raises the intent. Use onToggleRequested"))

    if call_sites < MINIMUM_CALL_SITES:
        print(f"ConfigSwitch intent lint FAILED: found only {call_sites} call "
              f"sites (expected at least {MINIMUM_CALL_SITES}) - the scan is "
              "matching almost nothing and would pass vacuously.",
              file=sys.stderr)
        return 1

    if violations:
        print("ConfigSwitch intent lint FAILED: a click is an intent, not a "
              "write to `checked` - assigning to a bound property destroys the "
              "binding and detaches the switch from the config (#158):",
              file=sys.stderr)
        for relative, line, detail in violations:
            print(f"  {relative}:{line}: {detail}", file=sys.stderr)
        return 1

    print(f"ConfigSwitch intent lint passed ({call_sites} call sites)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
