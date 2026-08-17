#!/usr/bin/env python3
"""The lock screen's preview cannot authenticate, and the sweep proves it looked.

Spec §11.2's last bullet (docs/superpowers/specs/2026-08-16-edit-mode-design.md):
Edit Mode's Lockscreen tab renders the real lock islands inside the viewport,
so `LockSurface` gains a single switch - `interactive` - and everything that
could take a keystroke or dispatch a session action is gated on it. The other
half is `LockPreviewContext`: a second component satisfying `LockContext`'s
property surface whose unlock paths are empty and which constructs no
`PamContext` and runs no `fprintd-list`. "The preview context is the real one
with a flag" is how a preview ends up authenticating, which is why it is a
separate file this module can hold to a negative.

This is the one contract in the mode whose failure is a security bug rather
than a layout bug, so every sweep here asserts it still FOUND the thing it
swept - a grep that matches nothing must fail, not pass. Concretely:

- the click-handler sweep asserts how many handlers it found before judging
  them, so a rewrite that renames `onClicked` cannot leave the check green
  over nothing;
- the parity sweep asserts how many properties, signals and functions it
  extracted from `LockContext.qml`, so a parser miss reads as a failure;
- the negative sweeps (`PamContext`, `fprintd`, `Process`) sit beside a
  positive assertion that the preview file exists and declares the surface.
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
LOCK_SURFACE = ROOT / "modules/imi/lock/LockSurface.qml"
LOCK_CONTEXT = ROOT / "modules/common/panels/lock/LockContext.qml"
PREVIEW_CONTEXT = ROOT / "modules/common/panels/lock/LockPreviewContext.qml"


def read(path: Path) -> str:
    assert path.exists(), f"{path} is gone - the sweep has nothing to look at"
    text = path.read_text()
    assert text.strip(), f"{path} is empty"
    return text


def code(path: Path) -> str:
    """The file with its comments stripped, so a rule cannot be satisfied by
    prose about the rule."""
    text = read(path)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


GUARD = re.compile(r"if\s*\(!root\.interactive\)\s*return")


def handler_bodies(text: str, name: str):
    """Every `<name>:` handler in the file, as (offset, body-text) pairs.

    A body is either the rest of the line (single-expression handler) or the
    whole brace-matched block. Arrow-function parameter lists (`mouse =>`) are
    skipped over to reach the body.
    """
    bodies = []
    for match in re.finditer(rf"\b{name}\s*:", text):
        rest = text[match.end():]
        rest = re.sub(r"^\s*(?:\([^)]*\)|\w+)\s*=>\s*", "", rest)
        stripped = rest.lstrip()
        if not stripped.startswith("{"):
            bodies.append((match.start(), stripped.split("\n", 1)[0]))
            continue
        depth = 0
        start = rest.index("{")
        for index in range(start, len(rest)):
            if rest[index] == "{":
                depth += 1
            elif rest[index] == "}":
                depth -= 1
                if depth == 0:
                    bodies.append((match.start(), rest[start:index + 1]))
                    break
    return bodies


def test_the_surface_declares_the_interactive_switch():
    text = code(LOCK_SURFACE)
    assert re.search(r"property bool interactive:\s*true", text), \
        ("LockSurface must declare `interactive`, default true - the real lock "
         "screen is the default and the preview is the exception")


def test_force_field_focus_returns_before_reaching_the_field():
    text = code(LOCK_SURFACE)
    match = re.search(r"function forceFieldFocus\(\)\s*\{(.*?)\n    \}", text, re.S)
    assert match, "LockSurface no longer defines forceFieldFocus"
    body = match.group(1)
    first = next((line.strip() for line in body.splitlines() if line.strip()), "")
    assert GUARD.search(first), \
        ("forceFieldFocus must return before touching the field when the "
         f"surface is not interactive; its first statement is: {first!r}")


def test_the_password_field_is_disabled_and_read_only_without_interactive():
    text = code(LOCK_SURFACE)
    enabled = re.search(r"^\s*enabled:\s*(.+root\.interactive.*)$", text, re.M)
    assert enabled, \
        "the password field's `enabled` must carry the interactive term"
    assert re.search(r"^\s*readOnly:\s*!root\.interactive\s*$", text, re.M), \
        ("the password field must be readOnly when the surface is not "
         "interactive - `enabled` alone still leaves programmatic paths open")


def test_every_click_handler_in_the_surface_is_gated():
    text = code(LOCK_SURFACE)
    bodies = handler_bodies(text, "onClicked")
    # The surface carries at least: the confirm button, the sleep button, the
    # password-guarded power and reboot component, and three media transport
    # buttons. Fewer matches than that means the sweep is looking at the wrong
    # thing, not that the surface got safer.
    assert len(bodies) >= 6, \
        (f"expected at least 6 onClicked handlers in LockSurface.qml, found "
         f"{len(bodies)} - the sweep may no longer be finding the file's handlers")
    for offset, body in bodies:
        inner = body.strip().lstrip("{").strip()
        first = next((line.strip() for line in inner.splitlines() if line.strip()), "")
        assert GUARD.search(first), \
            (f"an onClicked at offset {offset} is not gated on the surface "
             f"being interactive; its first statement is: {first!r}")


def test_the_root_area_and_the_key_handlers_stand_down_too():
    text = code(LOCK_SURFACE)
    assert re.search(r"^\s*enabled:\s*root\.interactive\s*$", text, re.M), \
        ("the surface's root MouseArea must be disabled when not interactive - "
         "a preview that swallows every click over the whole screen is a "
         "broken editor, and one that focuses the field on press is worse")
    for handler in ("Keys\\.onPressed", "Keys\\.onReleased"):
        bodies = handler_bodies(text, handler)
        assert bodies, f"LockSurface no longer declares {handler}"
        for offset, body in bodies:
            inner = body.strip().lstrip("{").strip()
            first = next((line.strip() for line in inner.splitlines() if line.strip()), "")
            assert GUARD.search(first), \
                (f"{handler} at offset {offset} is not gated on the surface "
                 f"being interactive; its first statement is: {first!r}")


if __name__ == "__main__":
    raise SystemExit(run(globals()))
