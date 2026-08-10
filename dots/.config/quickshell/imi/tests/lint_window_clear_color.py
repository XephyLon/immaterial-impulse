#!/usr/bin/env python3
"""Fail if a window's clear colour is bound to an expression instead of a constant.

A `PanelWindow`/`FloatingWindow`/`PopupWindow` `color:` is the QQuickWindow clear
colour, and Qt treats a change in its *alpha class* as a change to the window's
requested surface format:

    QQuickWindow::setColor()  ->  fmt.setAlphaBufferSize(alpha < 255 ? 8 : -1)
                              ->  QWindow::setFormat(fmt)

`QWaylandWindow::isOpaque()` is literally
`window()->requestedFormat().alphaBufferSize() <= 0`, and the next `setGeometry()`
or `setMask()` on an opaque window publishes `wl_surface.set_opaque_region` over
the whole window. Nothing in Qt ever retracts that region when the colour goes
translucent again - `setOpaqueArea()` has no caller outside those two `isOpaque()`
branches. Hyprland skips blur behind a client-declared opaque region, so a window
whose clear colour touches alpha 255 once is unblurred for the rest of the
process, however translucent it looks afterwards.

That is #143: `Settings.qml` bound its clear colour to `colLayer0`, whose alpha
collapses to 255 when `appearance.transparency.enable` goes off, so one
Settings > Transparency round trip cost the Settings window its frost until the
shell was reloaded and the window rebuilt.

Paint the backdrop with a child `Rectangle` instead and keep the clear colour a
literal. This check cannot be a QML test: Quickshell's plugin does not load in
`qmltestrunner`, so no window type here can even be constructed.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Quickshell window types whose `color` reaches QQuickWindow::setColor.
WINDOW_TYPES = {"PanelWindow", "FloatingWindow", "PopupWindow"}

# Reviewed exceptions. Adding one means arguing that the latch is harmless for
# that surface, not that the binding is fine.
#
# Background.qml's clear colour flips between "transparent" and an opaque safety
# tint, so it latches the same way - but it is the bottom-most surface on the
# screen. A stale opaque region there occludes nothing (there is nothing behind
# the background layer), and blur behind it has nothing to sample either, so the
# latch has no visible consequence. Painting the tint as a child instead would
# mean reordering the wallpaper/parallax/widget stack that surface carries,
# which is a much larger change than the defect justifies.
ALLOWED = {"modules/imi/background/Background.qml"}

OBJECT_OPEN = re.compile(r"^\s*(?:[A-Za-z_]\w*\.)*([A-Z]\w*)\s*\{")
COLOR_BINDING = re.compile(r"^\s*color\s*:\s*(\S.*?)\s*$")
STRING_LITERAL = re.compile(r'^(?:"[^"]*"|\'[^\']*\')$')


def _strip(line):
    """Drop line comments and string bodies so brace counting stays honest."""
    line = re.sub(r'"[^"]*"', '""', line)
    line = re.sub(r"'[^']*'", "''", line)
    return line.split("//", 1)[0]


def offending_bindings(text):
    """(line number, expression) for every window `color:` that is not a literal."""
    found = []
    stack = []
    for lineno, raw in enumerate(text.splitlines(), 1):
        code = _strip(raw)

        binding = COLOR_BINDING.match(raw.split("//", 1)[0])
        if binding and stack and stack[-1] in WINDOW_TYPES:
            expression = binding.group(1)
            if not STRING_LITERAL.match(expression):
                found.append((lineno, expression))

        opened = OBJECT_OPEN.match(code)
        pending = opened.group(1) if opened else None
        for char in code:
            if char == "{":
                stack.append(pending)
                pending = None
            elif char == "}" and stack:
                stack.pop()
    return found


def scan():
    offenders = {}
    for path in sorted(ROOT.rglob("*.qml")):
        if not path.is_file():
            continue
        if str(path.relative_to(ROOT)) in ALLOWED:
            continue
        hits = offending_bindings(path.read_text(errors="ignore"))
        if hits:
            offenders[str(path.relative_to(ROOT))] = hits
    return offenders


class WindowClearColorLint(unittest.TestCase):
    def test_the_scanner_sees_a_bound_window_colour(self):
        self.assertEqual(
            offending_bindings(
                'FloatingWindow {\n    color: Appearance.colors.colLayer0\n}\n'),
            [(2, "Appearance.colors.colLayer0")])

    def test_a_literal_clear_colour_passes(self):
        self.assertEqual(
            offending_bindings('PanelWindow {\n    color: "transparent"\n}\n'), [])

    def test_a_nested_rectangle_is_not_the_window(self):
        self.assertEqual(
            offending_bindings(
                'PanelWindow {\n'
                '    color: "transparent"\n'
                '    Rectangle {\n'
                '        color: Appearance.colors.colLayer0\n'
                '    }\n'
                '}\n'),
            [])

    def test_every_reviewed_exception_still_exists(self):
        for allowed in sorted(ALLOWED):
            self.assertTrue((ROOT / allowed).is_file(),
                            f"{allowed} is allowlisted but no longer exists; "
                            "drop the entry rather than leaving it dangling")

    def test_no_window_binds_its_clear_colour(self):
        offenders = scan()
        self.assertEqual(offenders, {}, "\n".join(
            f"{path}:{lineno}: window clear colour is bound to `{expression}`; "
            "use a literal and paint the backdrop with a child Rectangle"
            for path, hits in offenders.items() for lineno, expression in hits))


if __name__ == "__main__":
    unittest.main(verbosity=2)
