#!/usr/bin/env python3
"""The polkit prompt is drawn out of the shell's own parts, not Material's.

Two rules, and both are things the shell got wrong once already.

**One password prompt, one control.** The lock screen and the polkit dialog are
the same interaction - a modal surface asking for the user's password - and they
were two different text fields: the lock screen's `ToolbarTextField` (a filled
pill, the shape every field in this shell has) and polkit's `MaterialTextField`,
which hands its container to QtQuick Controls' Material style
(`Material.containerStyle: Material.Outlined`) and draws a boxed outline with the
prompt floating in a notch cut through it. That shape appears nowhere else here.
The check reads the LOCK screen's own field type rather than naming a type in a
string, so the two cannot drift apart by a rename.

**Exactly one filled button, and it is the confirming one.** Cancel and OK were
both flat, so the one question a modal authentication prompt has to answer - which
of these two is what you came here to do - had no answer in the picture at all.
`modules/imi/editMode/EditModeChromeContent.qml`'s `doneButton` records the same
failure from the other end and the same fix: a filled container on the primary
role. Two filled buttons reintroduce the problem from the other side, so the
count is pinned as well as the placement.

Every sweep asserts it FOUND what it swept for. A regex over QML that matches
nothing reads exactly like a regex over QML that found nothing wrong, and this
file's whole job is to hold a shape that a rewrite would spell differently.
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
POLKIT = ROOT / "modules/imi/polkit/PolkitContent.qml"
LOCK_SURFACE = ROOT / "modules/imi/lock/LockSurface.qml"
WINDOW_DIALOG = ROOT / "modules/common/widgets/WindowDialog.qml"


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


def blocks(text: str, type_name: str):
    """Every `<type_name> { ... }` declaration in the file, brace-matched.

    Brace matching rather than a line scan, because both button declarations
    span several lines and every property this file judges sits on one of the
    continuation lines - a line-scoped check finds the opening brace and reports
    a clean tree.
    """
    found = []
    for opener in re.finditer(rf"(?<![\w.]){re.escape(type_name)}\s*\{{", text):
        start = opener.end() - 1
        depth = 0
        for index in range(start, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    found.append(text[start:index + 1])
                    break
    return found


def password_field_type(text: str) -> str:
    """The type of the INNERMOST declaration that publishes itself as the lock
    screen's password field.

    Anchored on the publication (`root.passwordField = ...`) rather than on a
    masking property, because every masking property now belongs to the shared
    control and would name that control's own file instead of the call site.
    Innermost, because every enclosing block contains the statement too - a scan
    that takes the first match answers with whatever the file's root object
    happens to be.
    """
    needle = text.find("root.passwordField = ")
    if needle < 0:
        return ""
    best = ""
    best_span = len(text) + 1
    for opener in re.finditer(r"(?<![\w.])([A-Z][A-Za-z0-9_]*)\s*\{", text):
        start = opener.end() - 1
        if start > needle:
            break
        depth = 0
        for index in range(start, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    if start < needle < index and index - start < best_span:
                        best, best_span = opener.group(1), index - start
                    break
    return best


def test_the_polkit_field_is_the_control_the_lock_screen_uses():
    polkit = code(POLKIT)
    lock = code(LOCK_SURFACE)

    lock_field = password_field_type(lock)
    assert lock_field, \
        ("no password field found in LockSurface.qml - this check derives the "
         "shell's password control from it and has nothing to compare against")
    assert lock_field not in ("Component", "Item"), \
        (f"the lock screen's password field resolved to {lock_field!r}, which is "
         "a container rather than a control - the anchor has moved")

    assert re.search(rf"(?<![\w.]){lock_field}\s*\{{[^}}]*id: inputField", polkit, re.S), \
        (f"the polkit prompt's field is not a {lock_field} - the shell's two "
         f"password prompts must be one control")
    assert "MaterialTextField" not in polkit, \
        ("MaterialTextField draws Material's outlined-with-a-notch container, "
         "which appears nowhere else in this shell")


def test_the_field_sits_on_the_tier_above_the_dialog_body():
    # WindowDialog paints its card m3surfaceContainerHigh, i.e. layer 3. A field
    # nested in it is the tier above; colLayer1 (ToolbarTextField's own default)
    # is a tier BELOW the card and reads as a hole punched in it.
    dialog = code(WINDOW_DIALOG)
    assert "m3colors.m3surfaceContainerHigh" in dialog, \
        ("WindowDialog no longer paints its card m3surfaceContainerHigh - the "
         "field's own layer choice below was derived from that")
    polkit = code(POLKIT)
    assert re.search(r"colBackground: Appearance\.colors\.colLayer4", polkit), \
        "the polkit field must fill on colLayer4, the tier above the dialog body"


def test_exactly_one_dialog_button_is_filled_and_it_confirms():
    polkit = code(POLKIT)
    buttons = blocks(polkit, "DialogButton")
    assert len(buttons) == 2, \
        f"expected the dialog's two buttons, found {len(buttons)}"

    filled = [b for b in buttons if "colBackground:" in b]
    assert len(filled) == 1, \
        (f"{len(filled)} of the dialog's buttons carry a container - exactly one "
         "must, or there is nothing to say which action the dialog is asking for")

    confirm = filled[0]
    assert "root.submit()" in confirm, \
        "the filled button is not the one that submits the response"
    assert "Appearance.colors.colPrimary" in confirm, \
        "the confirming button's container must be the primary role"
    assert "colEnabled: Appearance.colors.colOnPrimary" in confirm, \
        ("the confirming button's label must be colOnPrimary - DialogButton's "
         "default colEnabled is colPrimary, which is its own container")

    cancel = [b for b in buttons if b is not confirm][0]
    assert "PolkitService.cancel()" in cancel, \
        "the flat button is not the one that cancels"


def test_the_dialog_card_casts_a_shadow_under_itself():
    dialog = code(WINDOW_DIALOG)
    shadow = re.search(r"StyledRectangularShadow\s*\{[^}]*target: dialogBackground", dialog, re.S)
    assert shadow, \
        ("WindowDialog's card casts no shadow - every other floating body in "
         "this shell pairs its surface with a StyledRectangularShadow")
    card = re.search(r"Rectangle\s*\{\s*id: dialogBackground", dialog)
    assert card, "WindowDialog's card is no longer `Rectangle { id: dialogBackground`"
    assert shadow.start() < card.start(), \
        ("the shadow is declared after the card, so it draws OVER it - siblings "
         "with no z stack in declaration order")


if __name__ == "__main__":
    raise SystemExit(run(globals()))
