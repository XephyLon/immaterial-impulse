#!/usr/bin/env python3
"""A widget draws its surface with WidgetCard, not with a hand-rolled tint.

The card exists because the same container was written four times - three
byte-identical `useBlurBackground ? applyAlpha(tint, opacity) : tint`
Rectangles in weather, currency and the media cookie, and a fourth in calendar
that had already drifted to a different rounding token and colour source. Four
copies is how container motion becomes four slightly different tunings.

So the pattern that built those copies is now reserved to the component: the
blur-thinned tint conditional may appear in WidgetCard.qml and nowhere else.
This does not force a widget to use the card (the system monitor's three cards
are its own composition); it forces a widget that wants the *standard* card
look to get it from the standard card, where its motion can be tuned once.

calendar/Widget.qml used to be exempted here, pending the rebuild the spec
scheduled for it. That rebuild has landed - it composes WidgetCard now, which
tests/test_expressive_design_system.py pins - so the exemption is gone. What
the widget still spells for itself is a *content* tint: the 1x1 banner, the
month pill, the day grid and today's highlight thin with the card so the frost
reads through the whole widget rather than through its edges only. That is
deliberately not what this reserves - those go through `transparentize`, which
scales an alpha two of those colours already carry, rather than the card's
absolute `applyAlpha`.

That carve-out was a spelling, and a spelling is not a rule. `notes` and
`image-converter` were both a root `Rectangle` painting
`blurEnabled ? transparentize(colSecondaryContainer, ...)`: the *card's* own
surface, written in the content tint's dialect, and so waved straight through
by a check matching only `useBlurBackground ? applyAlpha(`. The cost was not
redundancy - a widget that paints its own root surface hides the card
underneath it, so those two were the only desktop widgets on the desktop
casting no shadow at all, and neither could have lifted on hover or drag if
one had been added. The carve-out is now scoped to where it was earned: a
content tint is a surface *inside* the card, so the second rule below reads
only the ROOT object of each desktop widget's entry point, whatever helper the
tint is spelled with. Nested tints stay free.

b362d8c80 ("feat(widgets): one card component for the surface every widget
redrew"), 486272dbe ("feat(calendar): draw the widget's surface on the shared
card"), and the audit that found the hole: docs/widget-standards-audit-2026-08-16.md G2.
"""

from pathlib import Path
import json
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", "__pycache__", "tests"}
BUNDLED = ROOT / "modules/common/plugins/bundled"

ALLOWED = {
    Path("modules/common/plugins/designsystem/widgets/WidgetCard.qml"),
}

# The tint conditional, however the alpha helper is qualified and whatever the
# tint colour is: `useBlurBackground ? <something>applyAlpha(...)`.
TINT_PAIR = re.compile(r"useBlurBackground\s*\?\s*[\w.]*applyAlpha\s*\(", re.I)

# Either alpha helper, however qualified. A card tint is recognised by where it
# is painted, not by which of the two spellings a widget reached for.
TINT_HELPER = re.compile(r"\b(?:applyAlpha|transparentize)\s*\(")

# `color: <something>` in a root object's body.
COLOR_BINDING = re.compile(r"^\s*color\s*:\s*(.*)$")
# Anything that starts a new binding, property or child object, which is what
# ends the previous binding's value - a QML binding has no terminator. The
# continuation lines of a wrapped ternary (`? ...`, `: ...`) match none of it.
STATEMENT_START = re.compile(
    r"^\s*(?:readonly\s+)?(?:required\s+)?(?:property\s+[\w<>.]+\s+)?"
    r"[\w.]+\s*(?::|\{)\s*")
# A binding that is nothing but a name: `color: root.cardColor`. One level of
# that indirection is followed, because renaming the expression into a property
# is the one-line way to put the surface back.
NAME_ONLY = re.compile(r"^(?:root\.)?([A-Za-z_]\w*)$")
PROPERTY_DECL = re.compile(
    r"^\s*(?:readonly\s+)?property\s+[\w<>.]+\s+(\w+)\s*:\s*(.*)$")


def strip_noise(text):
    """Comments and string literals blanked out, newlines preserved.

    A brace inside either would move the depth counter, and the depth is how
    the root object's own body is told from everything nested inside it.
    """
    out = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "/" and text[i:i + 2] == "//":
            end = text.find("\n", i)
            end = len(text) if end == -1 else end
            out.append(" " * (end - i))
            i = end
        elif ch == "/" and text[i:i + 2] == "/*":
            end = text.find("*/", i + 2)
            end = len(text) if end == -1 else end + 2
            out.append("".join(c if c == "\n" else " " for c in text[i:end]))
            i = end
        elif ch in "\"'":
            j = i + 1
            while j < len(text) and text[j] != ch:
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, len(text))
            out.append("".join(c if c == "\n" else " " for c in text[i:j]))
            i = j
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def root_body_lines(text):
    """(line number, line) for every line inside the root object's own body.

    Depth 1 relative to the root's opening brace. A widget's card surface is
    painted here; a content tint is painted deeper.
    """
    clean = strip_noise(text)
    depth = 0
    root_open = None
    lines = []
    line_no = 1
    line_start_depth = 0
    line_start = 0
    for i, ch in enumerate(clean):
        if ch == "\n":
            if root_open is not None and line_start_depth == 1:
                lines.append((line_no, clean[line_start:i]))
            line_no += 1
            line_start = i + 1
            line_start_depth = depth
        elif ch == "{":
            depth += 1
            if root_open is None:
                root_open = i
                line_start_depth = 1
                line_start = i + 1
        elif ch == "}":
            depth -= 1
    return lines


def binding_value(lines, index):
    """The whole of a binding's value, wrapped ternary included."""
    value = [COLOR_BINDING.match(lines[index][1]).group(1).strip()]
    for _, line in lines[index + 1:]:
        if not line.strip() or STATEMENT_START.match(line):
            break
        value.append(line.strip())
    return " ".join(value).strip()


def resolve_once(lines, value):
    """`color: root.cardColor` followed to that property's own value."""
    name = NAME_ONLY.match(value)
    if not name:
        return value
    for index, (_, line) in enumerate(lines):
        declaration = PROPERTY_DECL.match(line)
        if declaration and declaration.group(1) == name.group(1):
            parts = [declaration.group(2).strip()]
            for _, following in lines[index + 1:]:
                if not following.strip() or STATEMENT_START.match(following):
                    break
                parts.append(following.strip())
            return " ".join(parts).strip()
    return value


def desktop_widget_entry_points():
    """Every bundled manifest's desktop-widget component, from the manifest.

    Read from the manifests rather than listed here, so a new desktop widget
    is covered on the day it ships. Bar and overlay widgets are deliberately
    out of scope: `discordVoice` is a panel, not a card on the desktop, and
    standard 3 does not reach it.
    """
    for manifest_path in sorted(BUNDLED.glob("*/manifest.json")):
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        if "desktop-widget" not in (manifest.get("capabilities") or []):
            continue
        component = (manifest.get("desktopWidget") or {}).get("component")
        if not component:
            continue
        entry = manifest_path.parent / component
        if entry.exists():
            yield entry


def main() -> int:
    failures = []
    for path in sorted(ROOT.rglob("*.qml")):
        rel = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in rel.parts) or rel in ALLOWED:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for match in TINT_PAIR.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            failures.append(
                f"{rel}:{line}: hand-rolled card tint. Use WidgetCard "
                f"(tint/useBlurBackground/backgroundOpacity) so the surface and "
                f"its motion are tuned in one place.")

    for entry in desktop_widget_entry_points():
        rel = entry.relative_to(ROOT)
        if rel in ALLOWED:
            continue
        try:
            text = entry.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        lines = root_body_lines(text)
        for index, (line_no, line) in enumerate(lines):
            if not COLOR_BINDING.match(line):
                continue
            value = resolve_once(lines, binding_value(lines, index))
            if "?" in value and TINT_HELPER.search(value):
                failures.append(
                    f"{rel}:{line_no}: the widget's ROOT paints a blur-thinned "
                    f"tint - that is the card's surface, and painting it here "
                    f"hides the card, its corner and its shadow. Compose "
                    f"WidgetCard; a *content* tint belongs on a surface inside "
                    f"it.")

    if failures:
        print("Widget card tint lint failed:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print("Widget card tint lint passed: the tint conditional lives in "
          "WidgetCard, and no desktop widget paints its own root")
    return 0


if __name__ == "__main__":
    sys.exit(main())
