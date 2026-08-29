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
BAR_POPUP_SLOT = ROOT / "modules/common/functions/bar_popup_slot.js"
BAR_CONTENT = ROOT / "modules/imi/bar/BarContent.qml"
VERTICAL_CONTENT = ROOT / "modules/imi/verticalBar/VerticalBarContent.qml"
CONTROLLER = ROOT / "modules/imi/bar/BarEditController.qml"
EDIT_ITEM = ROOT / "modules/imi/bar/BarWidgetEditItem.qml"
BAR_GROUP = ROOT / "modules/imi/bar/BarGroup.qml"
BADGE = ROOT / "modules/common/widgets/EditRemoveBadge.qml"
REORDER_AREA = ROOT / "modules/common/widgets/ReorderDragArea.qml"
CANVAS = ROOT / "modules/common/widgets/widgetCanvas/WidgetCanvas.qml"


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
    # deliberate, pre-existing teardown for the lock; the mode may not add one
    # for AUTO-HIDE SUSPENSION - holding a panel on screen goes through
    # mustShow/reveal, never through visible.
    #
    # `editLockPreview` is the sanctioned exception, and it is the OPPOSITE
    # gesture: on Edit Mode's Lockscreen tab the panels disappear exactly as
    # they do on the real lock (spec §1.5 - "the Lockscreen tab adds a term to
    # each"), so it rides the same teardown screenLocked already takes, cost
    # and all. The rule this check holds is therefore spelled by name: no
    # `visible` may be gated on editMode itself.
    for path in (BAR, VERTICAL_BAR, DOCK):
        for line in code(path).splitlines():
            if re.search(r"\bvisible\s*:", line) and "editMode" in line:
                raise AssertionError(
                    f"{path.name} gates a visible on editMode: {line.strip()} "
                    f"- on a layer surface that destroys the surface")


def test_the_panels_leave_the_lockscreen_tab_the_way_they_leave_the_lock():
    # Spec §1.5: on the Lockscreen tab the bar and the dock simply disappear,
    # and both halves of "disappear" already exist as the real lock's own
    # gates - the bars' loader `active` and the dock surface's `visible`. The
    # tab adds `!GlobalStates.editLockPreview` beside `!screenLocked` in each,
    # inheriting the same teardown/rebuild per tab flip the lock already pays
    # (the dock embeds no renderer, so a rebuilt GL context is acceptable
    # there - and noted, not assumed, per the spec's own caveat).
    for path in (BAR, VERTICAL_BAR):
        text = code(path)
        loader = re.search(r"active:\s*GlobalStates\.barOpen\s*&&\s*"
                           r"!GlobalStates\.screenLocked\s*\n?\s*&&\s*"
                           r"!GlobalStates\.editLockPreview", text)
        assert loader, \
            f"{path.name}'s loader does not stand down for the Lockscreen tab"
    dock = code(DOCK)
    assert re.search(r"visible:\s*!GlobalStates\.screenLocked\s*\n?\s*&&\s*"
                     r"!GlobalStates\.editLockPreview", dock), \
        "the dock does not stand down for the Lockscreen tab"


def test_a_bar_popup_cannot_claim_the_card_while_the_mode_is_on():
    # The mode makes the bar's widgets inert; a hover popup opening over an
    # inert bar is the widget answering the pointer after all, through a
    # HoverHandler or a claim path the input eater cannot reach.
    #
    # The refusal used to be inside StyledPopup's claimSlot, and this test
    # read it there. It has moved with the rest of the arbitration: the popup
    # only ASKS now, and the rules live with the slot - the decision in
    # bar_popup_slot.js, driven by the singleton that owns the slot. So the
    # wiring is what is checked here, and the refusal itself is asserted
    # behaviourally in tests/tst_bar_popup_slot.qml, which can simply call it.
    decision = code(BAR_POPUP_SLOT)
    assert "if (!state || state.editMode) return REFUSE;" in decision, (
        "the slot's decision no longer refuses under Edit Mode - a hover "
        "while editing would put a popup card over the bar being edited")

    states = code(GLOBAL_STATES)
    claim = re.search(r"function claimBarPopup\(popup\): bool \{(.*?)\n    \}", states, re.S)
    assert claim, "GlobalStates no longer declares claimBarPopup"
    assert "editMode: root.editMode" in claim.group(1), (
        "claimBarPopup does not pass the mode into the decision, so the "
        "refusal above can never fire")


def test_entering_the_mode_dismisses_whatever_popup_holds_the_card():
    # The gate above stops NEW claims; a popup already holding the card when
    # the mode opens has to be dismissed, or its card sits over the bar for
    # the whole session. GlobalStates already owns the mode's entry/exit
    # housekeeping (the drawer and the menu close there), so the dismissal
    # lives beside it.
    states = code(GLOBAL_STATES)
    handler = re.search(r"onEditModeChanged:\s*{(.*?)\n    }", states, re.S)
    assert handler, "GlobalStates no longer answers the mode changing"
    assert "vacateBarPopup()" in handler.group(1), (
        "entering the mode leaves whatever bar popup was open holding the "
        "shared card, over the bar being edited")


# ---- the two content trees carry the same edit machinery -------------------

def function_body(text: str, name: str) -> str:
    """A QML function's body by brace matching - the same block read the
    parity test uses, minimal because these two functions are short."""
    start = text.find(f"function {name}(")
    assert start != -1, f"no `function {name}` found"
    open_brace = text.index("{", start)
    depth = 0
    for index in range(open_brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace:index + 1]
    raise AssertionError(f"unbalanced braces in `function {name}`")


def test_both_trees_run_one_edit_predicate_and_one_slot_walk():
    # `widgetVisible` maps a drag's visible indices back to stored ones, and a
    # predicate that drifted from the other bar's would shift a drag by one
    # hidden entry - on the orientation nobody runs by default. Identical text
    # is the strongest cheap pin; the repeater ids are deliberately named the
    # same in both trees so `editSlotItems` can be identical too.
    for name in ("widgetVisible", "editSlotItems"):
        horizontal = " ".join(function_body(code(BAR_CONTENT), name).split())
        vertical = " ".join(function_body(code(VERTICAL_CONTENT), name).split())
        assert horizontal == vertical, (
            f"the two bars' {name} have diverged:\n"
            f"  horizontal: {horizontal}\n  vertical:   {vertical}")


def test_every_bucket_delegate_in_both_trees_wires_the_edit_overlay():
    # Six BarGroup delegates per tree (three buckets, two styles), and every
    # one passes the controller, its bucket and its widget id. A delegate that
    # misses the wiring is a widget that silently stays live and unbadged in
    # the mode - and only in the style and orientation that missed it.
    for path in (BAR_CONTENT, VERTICAL_CONTENT):
        text = code(path)
        controllers = text.count("editController: barEditController")
        assert controllers == 6, (
            f"{path.name} wires editController into {controllers} delegates, "
            f"not 6 - a bucket or a style is missing its edit overlay")
        for bucket in ("left", "middle", "right"):
            count = text.count(f'editBucket: "{bucket}"')
            assert count == 2, (
                f'{path.name} declares editBucket: "{bucket}" {count} times, '
                f"not 2 (one per style)")
        assert text.count("widgetId: modelData") == 6, (
            f"{path.name} does not hand every delegate its widget id")


def test_each_tree_instantiates_the_controller_at_its_own_orientation():
    horizontal = code(BAR_CONTENT)
    vertical = code(VERTICAL_CONTENT)
    assert re.search(r"BarEditController\s*{[^}]*vertical:\s*false", horizontal), (
        "BarContent's controller is not declared horizontal")
    assert re.search(r"Bar\.BarEditController\s*{[^}]*vertical:\s*true", vertical), (
        "VerticalBarContent's controller is not declared vertical - the "
        "reorder would compare the axis a column does not run along, which is "
        "the inert comparison the dock already shipped once")


def test_the_widgets_are_inert_through_an_eater_and_not_through_enabled():
    # `enabled: false` on a MouseArea disables that area and nothing under it,
    # and disabling the whole subtree runs every control's own disabled dim at
    # once. The eater intercepts the click, the hover and the wheel without
    # touching a binding in the widget below.
    item = code(EDIT_ITEM)
    assert "acceptedButtons: Qt.AllButtons" in item, (
        "the edit overlay's eater no longer takes every button - a right-click "
        "would fall through to the widget being edited")
    assert "hoverEnabled: true" in item, (
        "the eater no longer takes hover - hover-revealed widget affordances "
        "would answer the pointer through an inert bar")
    assert re.search(r"onWheel:.*\n?.*accepted = true", item), (
        "the eater no longer accepts wheel - an unhandled wheel propagates to "
        "whatever scrollable the widget carries")
    for path in (BAR_GROUP, EDIT_ITEM):
        assert not re.search(r"^\s*enabled\s*:\s*(false|!)", code(path), re.M), (
            f"{path.name} reaches for enabled to make the widget inert - "
            f"that is the cascade AGENT.md warns about, in either direction")


def test_the_remove_badge_is_the_shared_control():
    assert "EditRemoveBadge" in code(EDIT_ITEM), (
        "the bar's edit overlay no longer uses the shared remove badge")
    badge = read(BADGE)
    assert re.search(r"^RippleButton\s*{", badge, re.M), (
        "EditRemoveBadge is not rooted on RippleButton - the cursor, the "
        "hover/press states and the single application of the interaction "
        "motion all come from the control")


def test_the_controller_commits_through_layout_ops_and_only_in_the_mode():
    controller = code(CONTROLLER)
    assert ".splice(" not in controller, (
        "BarEditController spells a splice itself - the reorder arithmetic "
        "lives in layout_ops.js, and this file has no DragHandler for "
        "lint_reorder_arithmetic to sweep it with")
    for call in ("LayoutOps.move", "LayoutOps.remove", "LayoutOps.insert",
                 "LayoutOps.nthVisible", "LayoutOps.insertionForVisible",
                 "LayoutOps.moveTargetForInsertion"):
        assert call in controller, (
            f"BarEditController no longer reaches {call} - a local respelling "
            f"is the fifth copy the module exists to prevent")
    for name in ("commitReorder", "removeAt"):
        body = function_body(controller, name)
        assert "GlobalStates.editMode" in body, (
            f"{name} commits without checking the mode - a drag that outlives "
            f"the mode (Done mid-gesture) would store an order the user "
            f"never chose")
    writes = re.findall(r"Config\.options\.bar\.layouts\.(\w+)\s*=", controller)
    assert sorted(set(writes)) == ["leftLayout", "middleLayout", "rightLayout"], (
        f"the controller's layout writes are {sorted(set(writes))} - three "
        f"literal paths, never a computed key")


def test_the_gesture_is_the_shared_component_with_no_local_arithmetic():
    item = code(EDIT_ITEM)
    assert "ReorderDragArea" in item, (
        "the bar's edit overlay no longer drives the shared reorder gesture")
    area = code(REORDER_AREA)
    assert "LayoutOps.dropTarget" in area, (
        "ReorderDragArea no longer asks layout_ops where the drop lands")


def test_the_overlay_stands_down_with_the_mode_itself():
    group = code(BAR_GROUP)
    loader = re.search(r"Loader\s*{[^{]*?active:([^\n]*)", group, re.S)
    assert loader and "GlobalStates.editMode" in loader.group(1), (
        "BarGroup's edit loader is not gated on the mode - an overlay left "
        "active outside it eats every click on the bar")


def test_escape_sees_a_bar_drag_and_can_cancel_it():
    canvas = code(CANVAS)
    assert "GlobalStates.editBarDragActive" in canvas, (
        "the exit ladder cannot see a bar drag in flight - Escape mid-drag "
        "would exit the mode instead of cancelling the gesture")
    assert "GlobalStates.editReorderCancel()" in canvas, (
        "the ladder's cancelGesture no longer reaches the bar's drag - the "
        "pointer grab is on another surface and the signal is the return path")
    states = code(GLOBAL_STATES)
    assert "signal editReorderCancel()" in states
    handler = re.search(r"onEditModeChanged:\s*{(.*?)\n    }", states, re.S)
    assert handler and "editBarDragActive = false" in handler.group(1), (
        "leaving the mode does not clear editBarDragActive - the overlays "
        "holding a drag are torn down with the mode, so no end-of-drag "
        "handler is guaranteed to run")


# ---- the dock's half --------------------------------------------------------

DRAG_APPS = ROOT / "modules/imi/dock/DragApps.qml"


def test_the_docks_pinned_icons_grow_the_badge_and_go_inert_in_the_mode():
    drag_apps = code(DRAG_APPS)
    loader = re.search(
        r"Loader\s*{[^{]*?active:\s*GlobalStates\.editMode(.*?)\n            }",
        drag_apps, re.S)
    assert loader, (
        "DragApps no longer loads an edit overlay gated on the mode - the "
        "pinned icons would stay launchable and unbadged while being arranged")
    overlay = loader.group(1)
    assert "acceptedButtons: Qt.AllButtons" in overlay, (
        "the dock's eater no longer takes every button - a middle-click would "
        "still launch, and a right-click still open the context menu")
    assert "EditRemoveBadge" in overlay, (
        "the dock's overlay lost its remove badge - presence on the dock "
        "would only be editable from Settings again")
    assert "LayoutOps.remove" in overlay, (
        "the badge's removal no longer goes through layout_ops - a local "
        "splice is the copy the module exists to prevent")


def test_the_docks_preview_popup_stands_down_for_the_mode():
    should_show = declaration(code(DRAG_APPS), "shouldShow")
    assert should_show and "GlobalStates.editMode" in should_show, (
        "the window-preview popup can open while the dock is being edited - "
        "a hover card over the icons being arranged, the same hole "
        "StyledPopup's claim gate closes on the bar")


# ---- the drawer's Bar and Dock sections ------------------------------------

DRAWER = ROOT / "modules/imi/editMode/EditModeDrawer.qml"
CHROME_SURFACE = ROOT / "modules/imi/editMode/EditModeChromeSurface.qml"


def test_the_drawer_offers_the_bar_catalogue_through_the_one_policy():
    drawer = code(DRAWER)
    assert "BarWidgets.offerFor(" in drawer, (
        "the drawer's bar section does not ask BarWidgets.offerFor - a local "
        "filter is the policy copy the promotion removed from BarConfig")
    assert "AppSearch" in drawer, (
        "the drawer's dock section no longer reads the desktop entries "
        "through AppSearch")


def test_the_drawer_still_writes_nothing():
    # Stage 5's discipline, held through the new sections: every gesture is a
    # signal and the chrome surface makes every store write - which is what
    # keeps the scope question answerable in one file per store.
    drawer = code(DRAWER)
    for spelling in ("Config.setNestedValue", "TaskbarApps.togglePin",
                     "PluginState.set"):
        assert spelling not in drawer, (
            f"the drawer calls {spelling} itself - it reports gestures, the "
            f"surface writes")
    assert not re.search(r"Config\.options\.[\w.]+\s*=(?!=)", drawer), (
        "the drawer assigns to Config.options - it reports gestures, the "
        "surface writes")


def test_the_surface_appends_bar_widgets_by_literal_path_and_pins_through_the_one_writer():
    surface = code(CHROME_SURFACE)
    body = function_body(surface, "appendBarWidget")
    assert "LayoutOps.insert(" in body, (
        "appendBarWidget no longer goes through layout_ops.insert")
    writes = re.findall(r"Config\.options\.bar\.layouts\.(\w+)\s*=", body)
    assert sorted(set(writes)) == ["leftLayout", "middleLayout", "rightLayout"], (
        f"appendBarWidget writes {sorted(set(writes))} - three literal paths, "
        f"never a computed key (an allowlist reachable through a variable is "
        f"not an allowlist)")
    assert "TaskbarApps.togglePin(" in surface, (
        "the dock's presence write no longer goes through its one existing "
        "writer - a second spelling of the pinnedApps edit is the drift "
        "layout_ops and togglePin each exist to prevent in their own stores")


if __name__ == "__main__":
    raise SystemExit(run(globals()))
