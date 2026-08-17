#!/usr/bin/env python3
"""Stage 8 of Edit Mode: the bar and the dock, edited in place at full size.

Spec §4.2 and §12 stage 8. The two panels are not scaled and are not tabs -
they stay on their own layer surfaces, and the mode edits them where they are.
Most of what is worth pinning here is silent on screen, and several of the
failure modes are ones this repo has already paid for once:

- suspending auto-hide by touching `visible` on a layer surface destroys the
  surface rather than hiding it (the wallpaper-engine strobe, AGENT.md's
  layer-shell section), so the suspension must be a TERM added to the existing
  show expressions and nothing else;
- the mode's viewport reservation is a function of CONFIGURATION only - a
  reservation that follows the suspension would resize the viewport on entry,
  which is b710ef731's moving target under every widget at once
  (`test_edit_mode_contract.py` holds that half; nothing here may weaken it);
- two content trees draw the same layouts (`BarContent.qml`,
  `VerticalBarContent.qml`), and a capability added to one and not the other
  is exactly how the two bars came to resolve widget files differently
  (a47462fcc) - so every edit affordance is pinned on BOTH;
- a reorder spelled out beside a DragHandler is the fifth copy
  `layout_ops.js` exists to prevent (`lint_reorder_arithmetic.py` holds that
  half for files that declare one; the controller below has no DragHandler, so
  its half is pinned here).
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
BAR = ROOT / "modules/imi/bar/Bar.qml"
VERTICAL_BAR = ROOT / "modules/imi/verticalBar/VerticalBar.qml"
DOCK = ROOT / "modules/imi/dock/Dock.qml"
STYLED_POPUP = ROOT / "modules/common/widgets/StyledPopup.qml"
GLOBAL_STATES = ROOT / "GlobalStates.qml"


def read(path: Path) -> str:
    assert path.exists(), f"{path} is missing - this check has nothing to say"
    return path.read_text()


def code(path: Path) -> str:
    """The file with comments removed, so a forbidden name in a rationale
    comment cannot fail its own rule."""
    text = re.sub(r"/\*.*?\*/", "", read(path), flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def declaration(text: str, name: str) -> str:
    """One property's whole value, continuation lines included - the same
    block-scoped read `test_edit_mode_contract.py` documents, because both
    bars' `mustShow` carries its terms across several lines."""
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = re.match(
            rf"^(\s*)(?:readonly\s+)?property\s+\w+\s+{name}:(.*)$", line)
        if not match:
            continue
        indent = len(match.group(1))
        body = [match.group(2)]
        for following in lines[index + 1:]:
            if following.strip() and len(following) - len(following.lstrip()) <= indent:
                break
            body.append(following)
        return "\n".join(body)
    return ""


# ---- the panels stay on screen for the mode, without touching a surface ----

def test_the_mode_is_a_term_of_the_bars_own_show_expression():
    for path in (BAR, VERTICAL_BAR):
        must_show = declaration(code(path), "mustShow")
        assert must_show, f"{path.name} no longer declares mustShow"
        assert "GlobalStates.editMode" in must_show, (
            f"{path.name}'s mustShow carries no editMode term - an auto-hidden "
            f"bar cannot be edited in place while it is off screen, and the "
            f"suspension must be a term of the existing expression, never a "
            f"write to visible (which destroys a layer surface)")


def test_the_mode_is_a_term_of_the_docks_reveal():
    reveal = declaration(code(DOCK), "reveal")
    assert reveal, "Dock.qml no longer declares reveal"
    assert "GlobalStates.editMode" in reveal, (
        "the dock's reveal carries no editMode term - a hidden dock cannot be "
        "edited in place, and the reveal is the sanctioned expression for "
        "holding it on screen (a centre offset, never a surface property)")


def test_suspension_never_reaches_a_surfaces_visible():
    # `visible: false` on a layer surface destroys it (AGENT.md, layer-shell
    # section). The dock's existing `visible: !GlobalStates.screenLocked` is a
    # deliberate, pre-existing teardown for the lock; the mode may not add one.
    for path in (BAR, VERTICAL_BAR, DOCK):
        for line in code(path).splitlines():
            if re.search(r"\bvisible\s*:", line) and "editMode" in line:
                raise AssertionError(
                    f"{path.name} gates a visible on editMode: {line.strip()} "
                    f"- on a layer surface that destroys the surface")


def test_a_bar_popup_cannot_claim_the_card_while_the_mode_is_on():
    # The mode makes the bar's widgets inert; a hover popup opening over an
    # inert bar is the widget answering the pointer after all, through a
    # HoverHandler or a claim path the input eater cannot reach. The refusal
    # lives in claimSlot because that is the one gate all three claim paths
    # (hover, popupVisible, completion) already share.
    popup = code(STYLED_POPUP)
    claim = re.search(r"function claimSlot\(\)\s*{(.*?)\n    }", popup, re.S)
    assert claim, "StyledPopup no longer declares claimSlot"
    assert "GlobalStates.editMode" in claim.group(1), (
        "claimSlot does not refuse while the mode is on - a hover while "
        "editing would put a popup card over the bar being edited")


def test_entering_the_mode_dismisses_whatever_popup_holds_the_card():
    # The gate above stops NEW claims; a popup already holding the card when
    # the mode opens has to be dismissed, or its card sits over the bar for
    # the whole session. GlobalStates already owns the mode's entry/exit
    # housekeeping (the drawer and the menu close there), so the dismissal
    # lives beside it.
    states = code(GLOBAL_STATES)
    handler = re.search(r"onEditModeChanged:\s*{(.*?)\n    }", states, re.S)
    assert handler, "GlobalStates no longer answers the mode changing"
    assert "activeBarPopup" in handler.group(1), (
        "entering the mode leaves whatever bar popup was open holding the "
        "shared card, over the bar being edited")


if __name__ == "__main__":
    raise SystemExit(run(globals()))
