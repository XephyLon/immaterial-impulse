#!/usr/bin/env python3
#
# Regression guard: a Control-derived widget does not redeclare a FINAL property.
#
# QQC2's `Control` and `AbstractButton` mark a handful of properties FINAL -
# `padding` and its six variants, `spacing`, `font`, `palette`, `icon` - and a
# QML file whose root derives from them cannot declare its own property under
# one of those names. The failure is not a warning: "Cannot override FINAL
# property" at load, and the component is never created, so the widget is
# simply missing from the shell while every static check stays green. That
# has now happened twice - CalendarHeaderButton, then the Docker bar widget the
# day it became a RippleButton with a `readonly property real
# horizontalPadding` - and both times the rule was already written down in
# AGENT.md. A rule broken twice with the note in place is a rule that has to be
# a check.
#
# The derivation is followed through the repo's own types: a file whose root
# is `RippleButton` is a Control because RippleButton.qml's root is a Button,
# and a file rooted in that file is one too. Root-level declarations only -
# a `Component { ... }` or a child item inside the file is its own scope.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# QQC2 types deriving from Control (which owns the FINAL padding family, spacing,
# font and palette) or AbstractButton (which adds icon).
QQC2_CONTROLS = {
    "Control", "AbstractButton", "Button", "RoundButton", "ToolButton", "TabButton",
    "DelayButton", "Switch", "CheckBox", "RadioButton", "ItemDelegate", "SwitchDelegate",
    "CheckDelegate", "RadioDelegate", "SwipeDelegate", "MenuItem", "MenuBarItem",
    "Slider", "RangeSlider", "Dial", "SpinBox", "Tumbler", "ComboBox", "TextField",
    "TextArea", "Label", "ProgressBar", "BusyIndicator", "ScrollBar", "ScrollIndicator",
    "PageIndicator", "Pane", "Frame", "GroupBox", "Page", "ToolBar", "TabBar", "MenuBar",
    "DialogButtonBox", "Container", "SplitView", "ScrollView", "Popup", "Dialog",
    "Drawer", "Menu", "ToolTip",
}
FINAL = {
    "padding", "topPadding", "leftPadding", "rightPadding", "bottomPadding",
    "horizontalPadding", "verticalPadding", "spacing", "font", "palette", "icon",
}

ROOT_TYPE = re.compile(r"^([A-Z][A-Za-z0-9_]*)\s*\{", re.M)
ROOT_PROPERTY = re.compile(
    r"^    (?:readonly |required |default )?property\s+[A-Za-z0-9_<>.]+\s+([A-Za-z_][A-Za-z0-9_]*)\b", re.M)
COMMENT = re.compile(r"//[^\n]*")


def root_type(text):
    match = ROOT_TYPE.search(COMMENT.sub("", text))
    return match.group(1) if match else None


def main():
    files = {p: p.read_text(encoding="utf-8", errors="replace")
             for p in ROOT.rglob("*.qml") if "node_modules" not in p.parts}
    roots = {p: root_type(t) for p, t in files.items()}

    # Fixpoint over the repo's own types: a file is a Control if its root is.
    controls = set(QQC2_CONTROLS)
    while True:
        grown = {p.stem for p, r in roots.items() if r in controls} - controls
        if not grown:
            break
        controls |= grown

    offenders = []
    for path, text in files.items():
        if roots[path] not in controls:
            continue
        for match in ROOT_PROPERTY.finditer(COMMENT.sub("", text)):
            if match.group(1) in FINAL:
                line = text[:text.find(match.group(0)) if match.group(0) in text else 0].count("\n") + 1
                offenders.append(f"{path.relative_to(ROOT)}:{line}: `{match.group(1)}` is FINAL on "
                                 f"{roots[path]} (a Control); the component would never be created")

    if offenders:
        print("lint_final_properties: a Control-derived widget redeclares a FINAL property:")
        for line in sorted(offenders):
            print("  " + line)
        return 1
    print(f"lint_final_properties: OK ({sum(1 for p in roots if roots[p] in controls)} Control-derived files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
