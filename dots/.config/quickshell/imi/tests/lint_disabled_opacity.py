#!/usr/bin/env python3
#
# Regression guard: the disabled-state dim is applied ONCE, at one layer.
#
# `opacity` composites multiplicatively down the scene graph, so two components
# in the same subtree each expressing "disabled" as `opacity: enabled ? 1 : 0.4`
# do not agree on 0.4 - they produce 0.16. `ConfigSwitch` shipped exactly that:
# its root is a `RippleButton`, which dims the whole control (the switch track
# included, since `StyledSwitch` has no dim of its own), and it then repeated the
# same binding on the icon, the label, the description and all three content
# slots. Disabled rows rendered at roughly a sixth opacity instead of two fifths,
# and the slots disagreed with each other: `trailingContent` had no second
# binding and so landed at 0.4 while `titleContent` and `detailContent` landed at
# 0.16.
#
# The rule: if a component's ROOT type already dims itself on `enabled`, nothing
# inside that component may dim on `enabled` again - not a nested binding, and
# not a nested instance of another self-dimming type.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = ROOT / "modules"

# A property of the root object: the repo indents QML with four spaces, so a
# root-level binding sits at one level and anything nested sits deeper.
#
# There are two ways a component says "disabled" now. The literal
# `opacity: enabled ? 1 : 0.4` is the original; a control that adopted the
# shared interaction model instead reads the dim off its driver
# (`interactionMotion.dimOpacity`), and the model resolves the disabled state
# from `enabled` itself. Both are a root-level dim and both must be recognised
# - a detector that only knows the literal quietly stops seeing the adopters,
# and the nested-dim rule below then passes vacuously for every component
# rooted on one.
DIM_SOURCE = r"(?:\benabled\b.*\?|\bdimOpacity\b)"
ROOT_DIM = re.compile(r"^ {1,4}opacity:.*" + DIM_SOURCE)
NESTED_DIM = re.compile(r"^ {5,}opacity:.*" + DIM_SOURCE)
ROOT_TYPE = re.compile(r"^([A-Z]\w*)\s*\{")
NESTED_TYPE = re.compile(r"^ {5,}([A-Z]\w*)\s*\{")

# The group entrance's shared dressing installs an `opacity` binding on every
# `appear`-declaring member of its target, so a `StaggerEntrance` nested inside
# a component whose root already dims is this lint's bug with the writer one
# component away: the member's dressed opacity multiplies with the root's dim,
# 0.4 becomes 0.16, and the members disagree with anything the dresser skipped.
# (The component's own guard skips a member that OWNS an `interactionMotion`,
# but the members inside a dimming control are ordinarily plain rows - the
# control is their ancestor, which is exactly what that guard cannot see.)
DRESSER_TYPES = ("StaggerEntrance",)
NESTED_DRESSER = re.compile(r"^ {5,}(" + "|".join(DRESSER_TYPES) + r")\s*\{")


def qml_files():
    return sorted(MODULES.rglob("*.qml"))


def root_type(lines):
    for line in lines:
        match = ROOT_TYPE.match(line)
        if match:
            return match.group(1)
    return None


def dimming(sources):
    """Files whose root object binds opacity to `enabled`."""
    return {
        path
        for path, lines in sources.items()
        if any(ROOT_DIM.match(line) for line in lines)
    }


def scan(sources, self_dimming):
    violations = []
    for path, lines in sources.items():
        if root_type(lines) not in self_dimming:
            continue
        for number, line in enumerate(lines, 1):
            if NESTED_DIM.match(line):
                violations.append((path, number, line.strip()))
                continue
            dresser = NESTED_DRESSER.match(line)
            if dresser:
                violations.append((path, number,
                                   f"{dresser.group(1)} installs an opacity "
                                   f"on every member it dresses"))
                continue
            nested = NESTED_TYPE.match(line)
            if nested and nested.group(1) in self_dimming:
                violations.append((path, number,
                                   f"nested self-dimming {nested.group(1)}"))
    return violations


# The dresser rule matches source text, so it is proven against a fixture that
# cannot drift: a dimming root type, a component rooted on it holding a nested
# StaggerEntrance (must redden), and the same dresser under a plain root (must
# not). The original nested-dim rule is proven the other way, by the pinned
# real-tree findings in main().
SELF_CHECK = {
    "Dimmer.qml": """
Button {
    opacity: enabled ? 1 : 0.4
}
""",
    "DimmedHost.qml": """
Dimmer {
    Column {
        StaggerEntrance {
            target: rows
        }
    }
}
""",
    "FreeHost.qml": """
Item {
    Column {
        StaggerEntrance {
            target: rows
        }
    }
}
""",
}


def self_check():
    sources = {Path(name): text.splitlines() for name, text in SELF_CHECK.items()}
    self_dimming = {path.stem for path in dimming(sources)}
    if self_dimming != {"Dimmer"}:
        return f"the fixture's dimming root resolved to {self_dimming or 'nothing'}"
    found = {(path.name, number) for path, number, _ in scan(sources, self_dimming)}
    if found != {("DimmedHost.qml", 4)}:
        return (f"the dresser scan resolved {sorted(found) or 'nothing'} on a "
                "fixture holding one nested StaggerEntrance inside a dimming "
                "root and one under a plain one")
    return None


def main():
    broken = self_check()
    if broken:
        print("Disabled-opacity lint FAILED its own self-check: "
              f"{broken}. The check below cannot be trusted.", file=sys.stderr)
        return 1

    files = qml_files()
    sources = {path: path.read_text(encoding="utf-8").splitlines() for path in files}

    # A type dims itself if its own declaration file binds opacity to `enabled`
    # on the root object. The type name is the file's basename.
    dimming_files = dimming(sources)
    self_dimming = {path.stem for path in dimming_files}

    # The check matches source text, so it would pass vacuously after a reformat
    # that moved these bindings. Pin what it is supposed to have found - by FILE,
    # not by type name: the plugin design system ships its own RippleButton, so a
    # name-level guard stays satisfied by the copy while the mainline one loses
    # its dim, which is the state in which flagging inner bindings is actively
    # wrong (they would be the only dim left).
    expected = {
        "common/widgets/RippleButton.qml",
        "common/widgets/StyledSpinBox.qml",
        "common/plugins/designsystem/widgets/RippleButton.qml",
    }
    found = {str(path.relative_to(MODULES)) for path in dimming_files}
    missing = expected - found
    if missing:
        print("Disabled-opacity lint FAILED: the scan found no root-level "
              f"disabled dim in {sorted(missing)} - the indentation assumption "
              "or those files' shape changed, and the check below is now "
              "vacuous.", file=sys.stderr)
        return 1

    violations = [(path.relative_to(MODULES), number, detail)
                  for path, number, detail in scan(sources, self_dimming)]

    if violations:
        print("Disabled-opacity lint FAILED: opacity composites, so a second "
              "`enabled ? 1 : x` inside a component whose root already dims "
              "renders at x*x, not x. Delete the inner one - the root covers "
              "the whole control:", file=sys.stderr)
        for rel, number, detail in violations:
            print(f"  {rel}:{number}: {detail}", file=sys.stderr)
        return 1

    print(f"Disabled-opacity lint passed ({len(files)} QML files, "
          f"{len(self_dimming)} self-dimming types)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
