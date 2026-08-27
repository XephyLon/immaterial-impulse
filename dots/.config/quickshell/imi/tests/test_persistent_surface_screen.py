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
0.30.0 ("opens strictly on the primary monitor instead of the currently
focused one"), and again after both sidebars followed it onto EdgeSlide.

So a persistent surface is one window PER SCREEN, each pinned to its own
output, and a latch - the focused monitor's name, read at the open edge and
held for the open - picks which of them opens. Read at the declaration that
carries the namespace, five things:

- it is a delegate of a `Variants` over `Quickshell.screens` and declares
  `screen: modelData` - the compositor never chooses;
- its `keyboardFocus:` and `mask:` read the target predicate, not just the
  open flag - N surfaces turning OnDemand on one open would leave the
  compositor to pick which gets the keyboard, and N masks would let every
  screen's edge eat clicks;
- an `exclusiveZone:` it declares reads that predicate too, or the panel
  reserves a strip on every monitor at once;
- nothing that REGISTERS globally is declared inside the delegate. An
  `IpcHandler` is registered by target name and a `GlobalShortcut` by name,
  so a second instance of either is a startup failure rather than a
  duplicate - which is the whole reason the right sidebar's handlers moved
  out to its Scope when its window became a family;
- the open edge resolves the focused monitor's window AFRESH
  (`windowForFocusedMonitor()`, which latches through `WM.focusedMonitor`,
  the shell's one window-manager facade) - never through the prefix
  toggles' already-open shortcut, which at the open edge is always taken.

And the rule is swept rather than listed, because the surface that gets this
wrong is the one nobody thought about: EVERY `.qml` under `modules/imi/`
that declares a `PanelWindow` has to name its screen one of four ways - the
family above, a `screen:` on the window itself, a type whose every call site
passes one, or a reasoned entry in `EXEMPT` below. The exemption register
runs both ways: an entry whose file has since been pinned fails too, so it
cannot rot into an allowlist nobody rechecks.

Every sweep asserts it FOUND what it swept for.
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
IMI = ROOT / "modules/imi"

# The per-screen families: namespace, the predicate their input gates read,
# and the handler that dispatches their open edge.
SURFACES = {
    ROOT / "modules/imi/overview/Overview.qml": ("quickshell:overview", "isTarget", "onOverviewOpenChanged"),
    ROOT / "modules/imi/sidebarRight/SidebarRight.qml": ("quickshell:sidebarRight", "isTarget", "onSidebarRightOpenChanged"),
    ROOT / "modules/imi/sidebarLeft/SidebarLeft.qml": ("quickshell:sidebarLeft", "isTarget", "onSidebarLeftOpenChanged"),
}

# Surfaces that are NOT per-screen families, with the reason each one is
# exempt. Every one of these is a window built by a `Loader`/`LazyLoader`
# gated on the gesture that asks for it: it is created on the open and
# destroyed on the close, so "the monitor focused at creation" IS "the
# monitor focused when the user asked", which is the behaviour #297 wants.
# The bug is a surface that OUTLIVES the gesture; these do not.
EXEMPT = {
    ROOT / "modules/imi/cheatsheet/Cheatsheet.qml":
        "built by cheatsheetLoader, whose `active` starts false and is set false again by hide() - "
        "the window exists only while the sheet is up, so it is created on the focused monitor",
    ROOT / "modules/imi/dropShelf/DropShelfPanel.qml":
        "built by a LazyLoader gated on GlobalStates.dropShelfOpen - created per open",
    ROOT / "modules/imi/mediaControls/MediaControls.qml":
        "built by a Loader gated on GlobalStates.mediaControlsOpen - created per open",
    ROOT / "modules/imi/onScreenDisplay/OnScreenDisplay.qml":
        "built by a Loader gated on GlobalStates.osdVolumeOpen - created per toast, which is "
        "also why an OSD has always appeared where the user is looking",
    ROOT / "modules/imi/onScreenKeyboard/OnScreenKeyboard.qml":
        "built by a Loader gated on GlobalStates.oskOpen - created per open",
    ROOT / "modules/imi/wallpaperSelector/WallpaperSelector.qml":
        "built by a Loader gated on `reallyOpen`, which is the open flag plus the exit animation - "
        "created per open and destroyed when the exit finishes",
    # The one exemption that is NOT "created per open", and the one residual
    # instance of #297 in the tree. Its Loader is `overlayOpen ||
    # OverlayContext.hasPinnedWidgets`, so pinning a widget makes the surface
    # persistent and the overlay then opens on whichever monitor had focus
    # when the pin happened. The family pattern does not apply unchanged:
    # OverlayContext holds ONE list of widget Items and this window's mask is
    # built from them, so N windows would each mask items living in another
    # window. Making the overlay per-screen is a change to OverlayContext,
    # not a wrap around the window, and is deliberately not attempted here.
    ROOT / "modules/imi/overlay/Overlay.qml":
        "persistent only while a widget is pinned, and OverlayContext holds one list of widget "
        "Items that exactly one window can host - per-screen needs that store split first (#297)",
}

GLOBAL_REGISTRARS = ("IpcHandler", "GlobalShortcut")


def read(path: Path) -> str:
    assert path.exists(), f"{path} is gone - the sweep has nothing to look at"
    text = path.read_text()
    assert text.strip(), f"{path} is empty"
    return text


def code(path: Path) -> str:
    """The file with its comments removed. A check that reads a file whose own
    header explains the interface otherwise reads the prose - c8810d5ef."""
    text = read(path)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def brace_match(text: str, open_index: int) -> int:
    """Index of the `}` closing the `{` at `open_index`."""
    depth = 0
    for index in range(open_index, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    raise AssertionError("unbalanced braces")


def blocks(text: str, type_name: str):
    """(start, block) for every `TypeName { ... }` declaration in `text`. A
    qualified use (`Bar.BarExclusiveZoneReserver {`) counts as the type."""
    found = []
    for opener in re.finditer(rf"(?<![\w.])(?:\w+\.)?{re.escape(type_name)}\s*\{{", text):
        start = opener.end() - 1
        found.append((opener.start(), text[opener.start():brace_match(text, start) + 1]))
    return found


def function_body(text: str, name: str):
    """The body of `function <name>(...)`, brace-matched rather than matched to
    a closing brace at a guessed indent."""
    match = re.search(rf"function\s+{re.escape(name)}\s*\([^)]*\)\s*(?::\s*\w+\s*)?\{{", text)
    if not match:
        return None
    return text[match.end():brace_match(text, match.end() - 1)]


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


def panel_window_files():
    """Every `.qml` under modules/imi/ that declares a PanelWindow, with its
    comment-stripped source. A file that only NAMES the type in prose (the edit
    mode drawer's drop handler explains why it is not one) is not a surface."""
    found = {}
    for path in sorted(IMI.rglob("*.qml")):
        text = code(path)
        if blocks(text, "PanelWindow"):
            found[path] = text
    assert len(found) > 20, \
        f"the sweep found only {len(found)} PanelWindow files under modules/imi - it is looking in the wrong place"
    return found


def declares_inline_component(text: str, start: int) -> str:
    """The name in `component X: PanelWindow {` when `start` is that
    PanelWindow, otherwise the empty string."""
    match = re.search(r"component\s+(\w+)\s*:\s*$", text[:start].rstrip() + " ")
    return match.group(1) if match else ""


def declared_type_name(text: str, path: Path, start: int) -> str:
    """The name a CALLER instantiates this window by, when the window names no
    screen where it is declared: the inline component's name for a
    `component X: PanelWindow`, the file's own type for a root PanelWindow.
    Empty when the declaration is nested inside something else in the file,
    which means no call site can reach it."""
    inline = declares_inline_component(text, start)
    if inline:
        return inline
    if re.fullmatch(r"(?:\s|pragma[^\n]*|import[^\n]*)*", text[:start]):
        return path.stem
    return ""


def instantiations(type_name: str):
    """Every `TypeName { ... }` in the tree that is a USE of the type rather
    than the `component TypeName:` declaring it."""
    sites = []
    for path in sorted(ROOT.rglob("*.qml")):
        text = code(path)
        for start, block in blocks(text, type_name):
            if declares_inline_component(text, start) == type_name:
                continue
            sites.append((path, block))
    return sites


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


def test_a_reserved_zone_is_reserved_on_the_target_screen_only():
    """An `exclusiveZone` is a protocol value on each surface, so a family of
    them reserves once per monitor. The left sidebar's pin is the live case:
    ungated, pinning it would push every workspace on every screen aside for a
    panel that is only ever on one of them. A literal 0 reserves nothing and
    needs no gate (it is written out because writing the property at all is
    what forces exclusionMode to Normal)."""
    checked = 0
    for path, (namespace, predicate, _) in SURFACES.items():
        text = code(path)
        name = path.relative_to(ROOT).as_posix()
        _, block = mapping_block(text, namespace, name)
        for value in top_level_value(block, "exclusiveZone"):
            checked += 1
            if re.fullmatch(r"0", value.strip()):
                continue
            assert predicate in value, \
                (f"{name}'s `exclusiveZone: {value}` ignores `{predicate}` - "
                 "every screen's surface would reserve the panel's width at once")
    assert checked, "no per-screen surface declares an exclusiveZone - the sweep found nothing"


def test_nothing_that_registers_globally_is_declared_per_screen():
    """`IpcHandler` is registered by its `target` and `GlobalShortcut` by its
    `name`; both are process-wide. Declared inside a Variants delegate they are
    instantiated once per monitor, and the second registration fails at
    startup - so the handlers belong to the Scope that owns the family, which
    is where the right sidebar's had to move when its window became one."""
    for path, (namespace, _, _) in SURFACES.items():
        text = code(path)
        name = path.relative_to(ROOT).as_posix()
        start, block = mapping_block(text, namespace, name)
        for registrar in GLOBAL_REGISTRARS:
            inside = blocks(block, registrar)
            assert not inside, \
                (f"{name} declares {len(inside)} {registrar} inside its per-screen "
                 f"{namespace} window - one per monitor, and the second registration "
                 "is a startup failure, not a duplicate")
            assert blocks(text, registrar), \
                (f"{name} declares no {registrar} at all any more - moving them out of "
                 "the window must not lose them")


def test_the_open_edge_latches_the_focused_monitor():
    for path, (namespace, _, handler) in SURFACES.items():
        text = code(path)
        name = path.relative_to(ROOT).as_posix()
        dispatchers = re.findall(rf"function\s+{handler}\s*\(", text)
        assert len(dispatchers) == 1, \
            (f"{name} has {len(dispatchers)} `{handler}` handlers - the open edge is "
             "dispatched once, at the scope, so the latch is written before any window "
             "reads it")
        body = function_body(text, handler)
        assert body, f"{name} has no `{handler}` handler - nothing dispatches its open edge"
        latch = function_body(text, "latchTarget")
        assert latch, f"{name} has no latchTarget() - nothing decides which screen opens"
        assert "WM.focusedMonitor" in latch, \
            (f"{name}'s latch reads focus from somewhere other than "
             "WM.focusedMonitor - the shell's one window-manager facade")
        # Nothing between the `=` and the call: `activeWindow = activeWindow ??
        # windowForFocusedMonitor()` still NAMES the latch and is the bug -
        # every open after the first keeps the first screen's window.
        assert re.search(r"activeWindow\s*=\s*\w+\.windowForFocusedMonitor\(\)", body), \
            (f"{name}'s `{handler}` does not resolve the focused monitor's window "
             "afresh into `activeWindow` - the first version reused the window "
             "already showing, and at the open edge the flag has just flipped, so "
             "every open after the first landed on the first screen (#297 reopened)")
        assert "targetWindow()" not in body, \
            (f"{name}'s `{handler}` goes through targetWindow(), whose already-open "
             "shortcut is for the prefix toggles, not the open edge")


def test_every_layer_surface_names_the_screen_it_lives_on():
    """The sweep. A PanelWindow under modules/imi/ is pinned by its family, by
    a `screen:` of its own, by every call site of the type it is declared as,
    or by a reason in EXEMPT. Nothing else ships."""
    unpinned = []
    by_caller = 0
    for path, text in panel_window_files().items():
        if path in SURFACES or path in EXEMPT:
            continue
        name = path.relative_to(ROOT).as_posix()
        for start, block in blocks(text, "PanelWindow"):
            if top_level_value(block, "screen"):
                continue
            type_name = declared_type_name(text, path, start)
            if not type_name:
                # Nested inside something else in the file, so no call site can
                # reach it and nothing outside can be passing it a screen.
                unpinned.append(name)
                continue
            sites = instantiations(type_name)
            assert sites, \
                (f"{name} declares a PanelWindow with no screen as `{type_name}`, and "
                 "nothing instantiates it - so nothing can be pinning it")
            for site_path, site in sites:
                assert top_level_value(site, "screen"), \
                    (f"{site_path.relative_to(ROOT).as_posix()} builds a `{type_name}` "
                     "without a `screen:` - the window is declared without one too, so "
                     "the compositor picks the monitor focused at creation (#297)")
            by_caller += 1
    assert not unpinned, \
        ("these surfaces name no screen and carry no exemption: "
         f"{unpinned} - give them the per-screen family, a `screen:`, or an entry in EXEMPT")
    assert by_caller, "no surface is pinned by its call sites - that branch swept nothing"


def test_the_exemption_register_runs_both_ways():
    """A register that only grows is an allowlist. An exempt file must still
    exist, still declare a PanelWindow, still have no screen of its own, and
    still carry a reason - so a surface that has since been pinned has to lose
    its entry rather than sit there unread."""
    swept = panel_window_files()
    for path, reason in EXEMPT.items():
        name = path.relative_to(ROOT).as_posix()
        assert reason.strip(), f"{name}'s exemption carries no reason"
        assert path in swept, \
            (f"{name} is exempt from the per-screen rule and declares no PanelWindow "
             "any more - drop the entry")
        for _, block in blocks(swept[path], "PanelWindow"):
            assert not top_level_value(block, "screen"), \
                (f"{name} names its own screen now - it does not need an exemption")
        assert path not in SURFACES, f"{name} is both a per-screen family and exempt"


if __name__ == "__main__":
    raise SystemExit(run(globals()))
