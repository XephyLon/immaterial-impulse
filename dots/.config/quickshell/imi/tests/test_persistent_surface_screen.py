#!/usr/bin/env python3
"""A persistent surface says which screen it lives on.

A PanelWindow with no `screen:` asks the compositor to choose: Quickshell
passes a null wl_output to get_layer_surface (wlr_layershell.cpp sets
compositorPicksScreen when the screen is unset), and Hyprland answers with the
monitor that has focus AT CREATION (LayerSurface.cpp: an empty monitor name
resolves to focusState()->monitor()). A window rebuilt on every open therefore
landed on the focused monitor every time. A window created once at boot lands
on whichever monitor had focus at boot and stays there for the life of the
shell - which is what #297 reported after the overview went persistent in
0.30.0: "opens strictly on the primary monitor instead of the currently
focused one".

So a persistent surface is one window PER SCREEN, each pinned to its own
output, and a latch - the focused monitor's name, read at the open edge and
held for the open - picks which of them opens. Read at the declaration that
carries the namespace, three things:

- it is a delegate of a `Variants` over `Quickshell.screens` and declares
  `screen: modelData` - the compositor never chooses;
- its `keyboardFocus:` and `mask:` read the target predicate, not just the
  open flag - N surfaces turning OnDemand on one open would leave the
  compositor to pick which gets the keyboard, and N masks would let every
  screen's edge eat clicks;
- the open edge resolves the focused monitor's window AFRESH
  (`windowForFocusedMonitor()`, which latches through `WM.focusedMonitor`,
  the shell's one window-manager facade) - never through the prefix
  toggles' already-open shortcut, which at the open edge is always taken.

Every sweep asserts it FOUND what it swept for.
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent

# Persistent surfaces (see test_exit_owned_surface_contract.py and
# test_persistent_sidebar_contract.py) and the predicate each one gates its
# input on. The sidebars carry the same latent shape (no `screen:` on a
# window created at boot) and are not listed yet: the left one reparents a
# single content tree between two windows, so per-screen there is a larger
# change than a wrap, and #297 is about the overview.
SURFACES = {
    ROOT / "modules/imi/overview/Overview.qml": ("quickshell:overview", "isTarget", "onOverviewOpenChanged"),
}


def read(path: Path) -> str:
    assert path.exists(), f"{path} is gone - the sweep has nothing to look at"
    text = path.read_text()
    assert text.strip(), f"{path} is empty"
    return text


def code(path: Path) -> str:
    text = read(path)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def blocks(text: str, type_name: str):
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
                    found.append((opener.start(), text[opener.start():index + 1]))
                    break
    return found


def mapping_block(text: str, namespace: str, name: str):
    owning = [(start, block) for start, block in blocks(text, "PanelWindow")
              if namespace in block]
    assert len(owning) == 1, \
        (f"{name} has {len(owning)} PanelWindow declarations carrying "
         f"{namespace} - this rule is about the one that maps it")
    return owning[0]


def top_level_value(block: str, prop: str):
    values = []
    depth = 0
    for line in block.splitlines():
        if depth == 1:
            match = re.match(rf"\s*{re.escape(prop)}\s*:(.*)", line)
            if match:
                values.append(match.group(1).strip())
        depth += line.count("{") - line.count("}")
    return values


def test_the_surface_is_one_window_per_screen_pinned_to_its_output():
    for path, (namespace, _, _) in SURFACES.items():
        text = code(path)
        name = path.relative_to(ROOT).as_posix()
        start, block = mapping_block(text, namespace, name)
        families = [(s, b) for s, b in blocks(text, "Variants")
                    if s < start < s + len(b)]
        assert len(families) == 1, \
            (f"{name}'s {namespace} window is not a Variants delegate - a "
             "persistent window with no screen of its own is created once, on "
             "whichever monitor had focus at boot, and never moves (#297)")
        models = top_level_value(families[0][1], "model")
        assert models and all("Quickshell.screens" in m for m in models), \
            (f"{name}'s window family iterates {models}, not Quickshell.screens")
        assert top_level_value(block, "screen") == ["modelData"], \
            (f"{name}'s {namespace} window declares `screen: "
             f"{top_level_value(block, 'screen')}` - it must pin itself to the "
             "delegate's screen, or the compositor picks one at creation")


def test_input_and_keyboard_follow_the_target_not_just_the_flag():
    for path, (namespace, predicate, _) in SURFACES.items():
        text = code(path)
        name = path.relative_to(ROOT).as_posix()
        _, block = mapping_block(text, namespace, name)
        values = top_level_value(block, "WlrLayershell.keyboardFocus")
        assert values, f"{name}'s window declares no `WlrLayershell.keyboardFocus:`"
        for value in values:
            assert predicate in value, \
                (f"{name}'s `WlrLayershell.keyboardFocus: {value}` ignores "
                 f"`{predicate}` - with one surface per screen every sibling "
                 "would turn OnDemand on the same open, and the compositor "
                 "would pick which of them gets the keyboard")
        # The mask is a Region block, so its gate is one level down.
        assert top_level_value(block, "mask"), f"{name}'s window declares no `mask:`"
        mask = re.search(r"mask\s*:\s*Region\s*\{(.*?)\}", block, flags=re.S)
        assert mask, f"{name}'s mask is not a Region"
        assert predicate in mask.group(1), \
            (f"{name}'s mask Region does not read `{predicate}` - every "
             "screen's surface would take input on one open")


def test_the_open_edge_latches_the_focused_monitor():
    for path, (namespace, _, handler) in SURFACES.items():
        text = code(path)
        name = path.relative_to(ROOT).as_posix()
        handlers = re.findall(rf"function\s+{handler}\s*\(\)\s*\{{(.*?)\n    \}}", text, flags=re.S)
        assert len(handlers) == 1, \
            (f"{name} has {len(handlers)} `{handler}` handlers - the open edge "
             "is dispatched once, at the scope, so the latch is written before "
             "any window reads it")
        latch = re.search(r"function\s+latchTarget\s*\(\)\s*\{(.*?)\}", text, flags=re.S)
        assert latch, f"{name} has no latchTarget() - nothing decides which screen opens"
        assert "WM.focusedMonitor" in latch.group(1), \
            (f"{name}'s latch reads focus from somewhere other than "
             "WM.focusedMonitor - the shell's one window-manager facade")
        assert "windowForFocusedMonitor()" in handlers[0], \
            (f"{name}'s `{handler}` does not resolve the focused monitor's window "
             "afresh - the first version reused the window already showing, and "
             "at the open edge the flag has just flipped, so every open after the "
             "first landed on the first screen (#297 reopened)")
        assert "targetWindow()" not in handlers[0], \
            (f"{name}'s `{handler}` goes through targetWindow(), whose already-open "
             "shortcut is for the prefix toggles, not the open edge")


if __name__ == "__main__":
    raise SystemExit(run(globals()))
