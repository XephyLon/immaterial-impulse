#!/usr/bin/env python3
"""What Edit Mode may do to the desktop, and what it may not.

Stages 3 and 4 of docs/superpowers/specs/2026-08-16-edit-mode-design.md: the
viewport and the desktop, plus the chrome surface's half of §11.2. The drawer,
the per-widget menu, the bar and the dock are later stages and are not here.

Five of these guard failures that are silent on screen:

- a second notion of "am I editing" (§11.2's one-predicate rule, the analogue of
  the dock's one-derivation lint) - four copies of a mode check is how three of
  them go stale;
- the mode written into the shrink instead of transformed into it: `scale` is a
  render-time transform precisely because x/y/width/height are what the
  parallax animates, what every clamp measures and what the frost samples, and
  folding a second meaning into them is what b710ef731 punished;
- something inside the viewport compensating for the viewport, which reads as
  correct at scale 1 and is wrong everywhere else;
- the mode WRITING the global widget lock rather than subtracting it, which
  destroys a stored preference and leaves the desktop unlocked afterwards;
- and the mid-drag exit committing rather than cancelling, which stores an
  unclamped overshoot - the defect 705e9006d fixed, where a real store held a
  widget at x: -852 on a 5120px screen.

The chrome surface adds three more of the same kind, none of which any harness
can see, because weston implements no wlr-layer-shell:

- a screen-sized surface whose input mask is not the chrome makes the desktop
  underneath unclickable, and the desktop underneath is the thing being edited;
- a namespace absent from rules.lua falls through the catch-all
  `ignore_alpha = 0.05`, under which that surface's transparent pixels ask the
  compositor to blur the whole screen;
- and a chrome surface taking keyboard focus sits in front of the background
  and swallows the Escape the exit ladder is answered on.

Four more came out of the first live load, and three of the four are silent in
the same way - they are geometry that is only wrong on a machine that has the
panel in question:

- two surfaces working out where the bar and the dock are separately, which
  frames a rectangle the desktop is not at, and only where the two derivations
  differ;
- a reservation that follows something which MOVES while the mode is on
  (auto-hide, a hover reveal, a fullscreen window), which resizes the viewport
  mid-edit - b710ef731's defect reached from a new direction;
- the chrome placed against the screen's own edges rather than against the
  usable area, which is what put the toolbar on the bar's widgets;
- and a tone drawn between the specular and the inner highlight, which turns
  the card's bevel into a bevel around a line.

The card's edge then came back a third time, as a whole-card judgement no
per-tone measurement had asked: three defensible tones summed to five drawn
pixels of piping at one strength round the whole perimeter, which is a border.
Two rules hold the replacement in place - nothing may be drawn INSIDE the card
(anything there misses `surround`'s mask and is a uniform line by construction),
and the one band outside it is one pixel wide with a flank a fraction of its
top, not merely less than it.
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
MODULE = ROOT / "modules/common/functions/edit_mode.js"
GLOBAL_STATES = ROOT / "GlobalStates.qml"
CONFIG = ROOT / "modules/common/Config.qml"
BACKGROUND = ROOT / "modules/imi/background/Background.qml"
CANVAS = ROOT / "modules/common/widgets/widgetCanvas/WidgetCanvas.qml"
WIDGET = ROOT / "modules/common/widgets/widgetCanvas/AbstractWidget.qml"
BACKGROUND_WIDGET = ROOT / "modules/imi/background/widgets/AbstractBackgroundWidget.qml"
PLUGIN_WIDGET = ROOT / "modules/common/plugins/PluginWidget.qml"
CLOCK_DEPTH = ROOT / "modules/common/functions/clockDepth.js"
CARD = ROOT / "modules/imi/background/EditModeCard.qml"
LOOK_PROBE = ROOT / "EditModeLookProbe.qml"
THEME_LOADER = ROOT / "services/MaterialThemeLoader.qml"
APPEARANCE = ROOT / "modules/common/Appearance.qml"
CHROME_SCOPE = ROOT / "modules/imi/editMode/EditModeChrome.qml"
CHROME_SURFACE = ROOT / "modules/imi/editMode/EditModeChromeSurface.qml"
CHROME_CONTENT = ROOT / "modules/imi/editMode/EditModeChromeContent.qml"
DRAWER = ROOT / "modules/imi/editMode/EditModeDrawer.qml"
MENU = ROOT / "modules/imi/editMode/EditWidgetMenu.qml"
MENU_CONTENT = ROOT / "modules/imi/editMode/EditWidgetMenuContent.qml"
INSETS = ROOT / "modules/imi/editMode/EditModeInsets.qml"
DESKTOP_MENU = ROOT / "modules/imi/desktopMenu/DesktopMenu.qml"
LOCK_SURFACE = ROOT / "modules/imi/lock/LockSurface.qml"
LOCK_PREVIEW_CONTEXT = ROOT / "modules/common/panels/lock/LockPreviewContext.qml"
RULES = ROOT.parents[1] / "hypr/hyprland/rules.lua"
BAR_CONTROLLER = ROOT / "modules/imi/bar/BarEditController.qml"
LOCK_REORDER = ROOT / "modules/imi/lock/LockIslandReorder.qml"
DRAG_APPS = ROOT / "modules/common/widgets/DragApps.qml"
CATALOGUE_ROW = ROOT / "modules/common/widgets/CatalogueRow.qml"

# Everything that takes part in the mode. Listed rather than globbed so a new
# participant is a deliberate addition to this list, which is where someone
# reads what the rules are.
PARTICIPANTS = [BACKGROUND, CANVAS, WIDGET, BACKGROUND_WIDGET, PLUGIN_WIDGET,
                CHROME_SCOPE, CHROME_SURFACE, CHROME_CONTENT, DRAWER,
                MENU, MENU_CONTENT]


def read(path: Path) -> str:
    assert path.exists(), f"{path} is missing - this check has nothing to say"
    return path.read_text()


def code(path: Path) -> str:
    """The file with its comments removed.

    Every check below that forbids a NAME has to read this rather than the raw
    text, because the comment explaining why the name is forbidden contains it.
    Three of these checks failed on their own rationale the first time they ran,
    which is a way for a rule to be unwritable rather than a way for it to be
    wrong.
    """
    text = re.sub(r"/\*.*?\*/", "", read(path), flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def declaration(text: str, name: str) -> str:
    """One property's whole value, continuation lines included.

    A line-scoped read of a QML property is the mistake this repo keeps making:
    `edgeRollOff` carries its guard on the first line and its arithmetic on the
    second, so a check that reads the line finds a comparison and passes on
    anything below it. Same lesson as the settled-span sweep.
    """
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = re.match(rf"^(\s*)(?:readonly\s+)?property\s+\w+\s+{name}:(.*)$", line)
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


def declared_z(text: str) -> dict:
    """The z each declared object states, keyed by its id.

    A scan rather than a block match because the objects in question are hundreds
    of lines apart and a brace matcher over this file is a second thing to be
    wrong. It records the FIRST z after each id, which is that object's own.
    """
    found, current = {}, None
    for line in text.splitlines():
        named = re.match(r"\s*id: (\w+)\s*$", line)
        if named:
            current = named.group(1)
            continue
        depth = re.match(r"\s*z: (-?\d+)\s*$", line)
        if depth and current is not None and current not in found:
            found[current] = int(depth.group(1))
    return found


def test_the_mode_is_ephemeral_state_and_not_a_setting():
    states = read(GLOBAL_STATES)
    assert re.search(r"property bool editMode:\s*false", states), \
        "GlobalStates must declare the mode"
    assert "editMode" not in read(CONFIG), \
        ("a persisted edit mode is a shell that comes back from a restart with "
         "the desktop shrunk and every affordance out")


def test_nothing_computes_the_mode_from_anything_but_the_one_flag():
    # A file may read GlobalStates.editMode, or take it as a property the owning
    # surface hands in (WidgetCanvas, which the overlay reuses and which must
    # never follow the mode). What it may not do is derive it from a second
    # source, because then there are two answers to one question.
    for path in PARTICIPANTS:
        text = read(path)
        for match in re.finditer(r"(?<![.\w])editMode\b", text):
            line = text[text.rfind("\n", 0, match.start()) + 1:
                        text.find("\n", match.start())]
            allowed = (
                "GlobalStates.editMode" in line
                # A declaration, and only with a neutral default: a property
                # DERIVED from something else is the second source.
                or re.search(r"property bool editMode: false\s*$", line)
                or "root.editMode" in line
                or "rootWidget.editMode" in line
                # The chrome surface's own layer-shell namespace, which is a
                # string and not a predicate at all.
                or "WlrLayershell.namespace" in line
                or line.lstrip().startswith("//")
            )
            assert allowed, f"{path.name}: a second source for the mode: {line.strip()}"


def test_the_viewport_is_a_transform_and_not_a_resize():
    text = read(BACKGROUND)
    # The three siblings that draw the desktop all take the SAME matrix, so
    # there is one arithmetic and they cannot drift a pixel apart.
    applied = re.findall(r"transform:\s*Matrix4x4\s*\{\s*matrix:\s*bgRoot\.editMatrix\s*\}", text)
    assert len(applied) == 4, \
        (f"expected the wallpaper viewport, the widget canvas, the clock depth "
         f"layer and the lock islands host to carry the edit transform, "
         f"found {len(applied)}")
    # Nothing may write the geometry the mode is supposed to leave alone.
    for prop in ("width", "height", "x", "y"):
        assert not re.search(rf"^\s*{prop}:[^\n]*editViewport", text, re.M), \
            f"the mode writes {prop} instead of transforming it"


def test_nothing_inside_the_viewport_compensates_for_the_viewport():
    # Recovering a screen coordinate by dividing by the scale is the tempting
    # way to write anything that has to reach outside the desktop, and it is
    # exactly the coupling the transform exists to avoid. The scale is
    # Background's alone; nothing else may even name it.
    for path in PARTICIPANTS:
        if path == BACKGROUND:
            continue
        text = read(path)
        assert "editMatrix" not in text and "editViewport" not in text, \
            f"{path.name} reaches for the viewport's own transform"
    background = read(BACKGROUND)
    matrix = re.search(r"readonly property matrix4x4 editMatrix: Qt\.matrix4x4\((.*?)\)\n",
                       background, re.S)
    assert matrix, "the transform is no longer written as one matrix"
    for match in re.finditer(r"editTransform\.(scale|x|y)", background):
        assert matrix.start() < match.start() < matrix.end(), \
            ("the viewport's own transform is used outside the matrix it "
             f"builds, at offset {match.start()}")


def test_the_escape_ladder_is_the_module_and_not_open_coded():
    text = read(CANVAS)
    assert 'import "../../functions/edit_mode.js" as EditMode' in text
    handler = re.search(r"Keys\.onEscapePressed:\s*\{(.*?)\n    \}", text, re.S)
    assert handler, "the canvas no longer answers Escape"
    body = handler.group(1)
    assert "EditMode.resolveEscape" in body, \
        "the ladder's precedence belongs to the module, where a test can reach it"
    # The answers the module gives, and no branch invented beside them.
    # `closeMenu` is the first rung: the per-widget menu is the topmost
    # transient the mode draws, so Escape dismisses it before touching what is
    # under it - and never exits the mode while it is up. `desktopTab` is the
    # rung the Lockscreen tab fires: without its branch the answer would fall
    # through to the exit and Escape on that tab would leave the mode instead
    # of returning to the Desktop tab.
    for answer in ("closeMenu", "cancelGesture", "clearSelection", "desktopTab"):
        assert answer in body, f"the handler ignores the module's {answer}"
    # And the tab the ladder is asked about is the real one. A hardcoded
    # DESKTOP_TAB here was correct while only one tab existed and silently
    # disarms the rung above the moment a second one does.
    assert "tab: GlobalStates.editTab" in body, \
        "the ladder must be asked about the tab that is actually showing"


def test_the_global_lock_is_suppressed_and_never_written():
    # A write would destroy a stored preference and leave the desktop unlocked
    # once the mode ended. Only the two places that mean "the user asked for the
    # lock to change" may write it.
    writers = {
        # A right-click on a widget: the one gesture left that means "change
        # the lock". WidgetsSubmenu was the other sanctioned writer and is
        # gone - its widget list had been empty since the desktop widgets
        # became plugins, and its only live control was this switch, which the
        # mode suppresses (spec §4.1: a switch that turns off something the
        # editor turns back on).
        "modules/common/widgets/widgetCanvas/AbstractWidget.qml",
    }
    seen = set()
    for path in ROOT.rglob("*.qml"):
        if "/tests/" in str(path) or path.name.endswith("RuntimeTest.qml"):
            continue
        for line in path.read_text().splitlines():
            if line.lstrip().startswith("//"):
                continue
            if not re.search(r"Config\.options\.background\.widgetsLocked\s*=(?!=)", line):
                continue
            relative = str(path.relative_to(ROOT))
            seen.add(relative)
            assert relative in writers, f"{relative} writes the global widget lock"
    assert seen == writers, f"a sanctioned writer disappeared: {writers - seen}"
    # ...and the suppression is a subtraction on the resolved lock.
    assert re.search(r"widgetsLocked\s*&&\s*!GlobalStates\.editMode",
                     read(BACKGROUND_WIDGET)), \
        "the mode must subtract the global term from interactionLocked"


def test_leaving_the_mode_mid_drag_cancels_the_gesture():
    canvas = read(CANVAS)
    assert re.search(r"onEditModeChanged:[^\n]*cancelActiveDrag", canvas), \
        "the mode ending must reach the drag"
    cancel = re.search(r"function widgetDragCancelled\(widget\)\s*\{(.*?)\n    \}", canvas, re.S)
    assert cancel, "the canvas has no cancel path for a group drag"
    assert "commitPosition" not in cancel.group(1), \
        ("a cancel that commits stores an unclamped overshoot: the drag is "
         "deliberately unclamped until the release that commits it")
    widget = read(WIDGET)
    assert re.search(r"function cancelDrag\(\)", widget)
    assert "restoreXYBinding" in widget, \
        "the pre-press position comes back through the binding, not by hand"
    # The release that follows a cancel is still coming, and must commit
    # nothing - what it would write is wherever the restore animation reached.
    assert re.search(r"dragCancelled\s*\)\s*\{", read(BACKGROUND_WIDGET)), \
        "the release after a cancel is not swallowed"


def test_the_frost_names_its_condition_rather_than_one_of_its_causes():
    text = read(PLUGIN_WIDGET)
    assert "lockCoversFrost" not in text, \
        "the gate has two producers now and may not be named for one of them"
    gate = re.search(r"readonly property bool frostSuspended:(.*?)\n    Repeater", text, re.S)
    assert gate, "PluginWidget no longer resolves whether its frost is suspended"
    assert "GlobalStates.editMode" in gate.group(1)
    assert "GlobalStates.screenLocked" in gate.group(1)
    assert "!rootWidget.frostSuspended" in text, "the blur Repeater ignores the gate"


def test_the_chrome_stands_down_through_two_gates_and_not_one():
    # Both are load-bearing and the pixel probe cannot see it: with the Loader
    # gated and the opacity not, the chrome is gone anyway, and vice versa - so
    # a frame comparison passes on a tree with one of them left. Which is
    # exactly why the second one gets deleted as redundant one day.
    text = read(BACKGROUND)
    chrome = re.search(r"Loader \{\s*id: editChrome(.*?)\n        \}", text, re.S)
    assert chrome, "the mode's chrome loader is gone"
    body = chrome.group(1)
    assert re.search(r"active:\s*bgRoot\.editProgress > 0", body), \
        "the chrome must not exist while the mode is off"
    assert re.search(r"opacity:\s*bgRoot\.editProgress", body), \
        "the chrome must be transparent while the mode is off"
    # ...and its geometry is the module's answer, not a second one.
    assert "card: bgRoot.editCard" in body and "cardRadius: bgRoot.editCardRadius" in body
    assert "EditMode.cardRect(" in text, \
        "the card's rectangle must come from the same arithmetic as the transform"


def test_the_lattice_declares_where_it_sits_rather_than_inheriting_it():
    # The desktop widgets are EXTERNAL children of the canvas, so declaration
    # order decides nothing here; a grid Rectangle at the canvas's root is back
    # to the stacking being whatever each Repeater's model happened to fill
    # first.
    text = read(CANVAS)
    lattice = re.search(r"Item \{\s*id: lattice(.*?)\n    \}", text, re.S)
    assert lattice, "the lattice is not one item any more"
    assert re.search(r"^\s*z: -1\s*$", lattice.group(1), re.M), \
        "the lattice must declare that it sits below the widgets"
    for match in re.finditer(r"gridSize\b", text):
        line_start = text.rfind("\n", 0, match.start()) + 1
        if not re.match(r"\s*(x|y|model):", text[line_start:match.start() + 8]):
            continue
        assert lattice.start() < match.start() < lattice.end(), \
            "a line of the lattice is drawn outside the item that owns its order"


def test_the_lattice_belongs_to_the_drag_and_not_to_the_mode():
    # "In Edit mode, the grid lines should not appear until I try to move a
    # widget." The reversal of §4.1's discoverability argument, which was
    # written before the mode had a toolbar of its own to say it is on.
    #
    # Read as a WHOLE declaration rather than as a line: this one is written
    # across two, with the `&&` on the continuation, and a line-scoped check
    # sees `root.showGrid` on its own and passes on anything.
    text = read(CANVAS)
    gate = re.search(
        r"readonly property bool gridVisible:((?:[^\n]*\n)(?:\s*(?:&&|\|\|)[^\n]*\n)*)", text)
    assert gate, "the canvas no longer resolves whether the lattice is drawn"
    body = " ".join(gate.group(1).split())
    # A gesture in flight is REQUIRED, so it is the leading conjunct and
    # everything after it is joined with `&&`. Written as a shape rather than as
    # "editMode must not appear" because the mode legitimately appears further
    # in - it is what overrides the config switch, inside the second operand.
    # Anything a top-level `||` reaches is a second way to draw the lattice with
    # nobody dragging, which is the thing being removed.
    assert body.startswith("root.showGrid"), \
        f"the lattice is not gated first on a gesture being in flight: {body}"
    rest = body[len("root.showGrid"):].strip()
    assert rest == "" or rest.startswith("&&"), \
        (f"the lattice has a way to be drawn that is not a gesture: {body} - "
         f"what the mode overrides is the config switch, not the gesture")

    # ...and the flag it is gated on follows the THRESHOLD rather than the
    # press. A widget's own controls - the grip, the right-click, a click that
    # selects - all press without travelling, and a lattice answering each of
    # them would be worse than one that never went away.
    widget = read(WIDGET)
    assert "drag.threshold" in widget, \
        "the drag no longer distinguishes a press from a move"
    pressed = re.search(r"onPressed: \(mouse\) => \{(.*?)\n    \}", widget, re.S)
    assert pressed, "AbstractWidget no longer answers a press"
    assert "dragActive" not in pressed.group(1), \
        "a press raises the drag flag, so the lattice would answer every click"
    changed = re.search(r"onDraggingChanged: \{(.*?)\n    \}", widget, re.S)
    assert changed and "setDragging(dragging)" in changed.group(1), \
        "the canvas is no longer told when a drag starts and stops"
    # The one end a drag has that onDraggingChanged never sees. The runtime
    # harness drives `widgetRemoved` directly, because a statically declared
    # widget cannot be destroy()ed - so what it cannot say is that a real
    # destruction reaches that function, and this is that half.
    destruction = re.search(r"Component\.onDestruction: \{(.*?)\n    \}", widget, re.S)
    assert destruction and "widgetRemoved" in destruction.group(1), \
        "a destroyed widget no longer tells the canvas it has gone"
    removed = re.search(r"function widgetRemoved\(widget\) \{(.*?)\n    \}", read(CANVAS), re.S)
    assert removed and "setDragging(false)" in removed.group(1), \
        ("a widget destroyed mid-drag leaves the lattice up: nothing else can "
         "take it down, because it never reaches onDraggingChanged")


def test_the_cover_that_rounds_the_corner_sits_below_the_widgets():
    # "There shouldn't be any clipping." The cover makes the card's corner by
    # covering it, and a cover over EVERYTHING covers the widgets too: the
    # desktop scales about its own centre, so the canvas's edge lands on the
    # card's edge and a widget parked against a screen edge is flush with the
    # rounding. At a corner it lost a bite - measured at 5120x1440, 20px along
    # each edge of a widget pinned there, which is where this machine's own
    # store keeps `visualizer`.
    order = declared_z(read(BACKGROUND))
    for name in ("editChrome", "widgetCanvas", "clockDepthLayer"):
        assert name in order, \
            f"{name} declares no z, so its order is whatever happened to build first"
    assert order["editChrome"] < order["widgetCanvas"], \
        (f"the mode's cover is at z {order['editChrome']} and the widget canvas at "
         f"{order['widgetCanvas']}: the rounding is cutting the widgets")

    # The look probe RE-DECLARES this arrangement, because weston implements no
    # layer shell and the real one cannot be stood up. That makes it a second
    # copy of the thing it scores, and a second copy drifts: it scored one
    # render of this fix against its own z: 4 and reported a widget whose corner
    # was visibly still being eaten.
    probe = declared_z(read(LOOK_PROBE))
    for name in ("editChrome", "widgetCanvas"):
        assert probe.get(name) == order[name], \
            (f"the look probe draws {name} at z {probe.get(name)} and Background.qml "
             f"at {order[name]}: the probe is scoring an arrangement the shell "
             f"does not have")


def test_the_cards_chrome_composites_once_and_only_once():
    # The card's edge is full-screen and is redrawn on every frame of a 400ms
    # shrink, so what it may cost is a standing constraint rather than a
    # one-off measurement: an effect that re-renders the backdrop per frame
    # would be felt. The bevel's two outer tones are Rectangles declared inside
    # `surround`, whose layer is already masked to the complement of the card -
    # they ride a mask that existed rather than bringing one.
    #
    # Measured over four runs each of an identical scripted sequence under
    # headless weston's SOFTWARE renderer, where a full-screen pass costs CPU
    # instead of being free: 14.91s +/- 0.22 of user CPU with the bevel against
    # 14.68s +/- 0.32 without, on a run-to-run spread of 3-4%. Indistinguishable.
    # That number is only true while the shape stays this one, which is what
    # this check is for - the way to break the finding is to add a second layer
    # later and never re-measure.
    text = read(CARD)
    layers = re.findall(r"^\s*layer\.enabled:\s*true\s*$", text, re.M)
    assert len(layers) == 1, \
        (f"the card composites through {len(layers)} layers: every one of them is a "
         f"full-screen render target reallocated for each frame of the shrink")
    effects = re.findall(r"^\s*layer\.effect:\s*(\w+)", text, re.M)
    assert effects == ["OpacityMask"], \
        f"the card's chrome runs {effects} over the backdrop, not one mask"
    # Declared objects rather than any mention of the name: the file's own
    # comments explain why a ShaderEffectSource renders its source in that
    # item's coordinates, and a check that reads prose is a check about prose.
    for expensive in ("GaussianBlur", "FastBlur", "MultiEffect", "ShaderEffect",
                      "ShaderEffectSource"):
        assert not re.search(rf"^\s*{expensive}\s*\{{", text, re.M), \
            (f"{expensive} in the card's chrome re-renders the backdrop the "
             f"component is arranged to render once")


def test_the_depth_layer_stands_down_for_the_mode():
    # The one thing left drawing above that cover, and it is above the widgets
    # by design - so it cannot be put under the cover without putting the
    # widgets under it too. It stands down instead, which it wants to anyway:
    # it paints the wallpaper's subject over the widgets the mode exists to let
    # the user arrange, and it reconstructs the parallax viewport, which is
    # larger than the screen and would be free to paint outside the card.
    assert re.search(r"if \(s\.editing\) return false;", read(CLOCK_DEPTH)), \
        "the eligibility predicate has no refusal for the mode"
    background = read(BACKGROUND)
    assert re.search(r"editing:\s*GlobalStates\.editMode", background), \
        "the depth layer never tells the predicate the mode is on"


def test_the_inset_is_derived_from_one_declared_drawer_width():
    module = read(MODULE)
    assert "function viewportGeometry" in module
    # Stage 5's drawer plugs into this number; a second one written into the
    # drawer would be two fields that must agree.
    appearance = read(ROOT / "modules/common/Appearance.qml")
    assert re.search(r"property real editModeDrawerWidth:\s*\d", appearance)
    assert "Appearance.sizes.editModeDrawerWidth" in read(BACKGROUND), \
        "the viewport must derive its inset from the drawer's declared width"
    assert not re.search(r"drawerOpen|drawerVisible", module), \
        ("the inset may not depend on the drawer being open - opening it "
         "translates the desktop, it never resizes it")


def test_the_drawer_reaches_the_desktops_x_and_nothing_else():
    """Opening the drawer translates the desktop; it never resizes it.

    Spec §1.3, mechanized: the drawer's open state may reach exactly one term
    of the transform - the shift `atProgress` applies to x - and may not reach
    the geometry at all. A width, height or scale that read it would rescale
    every widget under the cursor mid-edit and hand every Behavior carrying
    the box a moving target (b710ef731). The failure is silent at rest, which
    is the only place anyone looks: open and closed settle correctly, and the
    frames in between rescale a drag in flight.
    """
    text = code(BACKGROUND)
    shift = declaration(text, "editShift")
    assert "EditMode.drawerTravel(" in shift, \
        "the desktop's travel must come from the module, not be worked out again"
    assert "GlobalStates.editDrawerProgress" in shift, \
        "the shift is the travel times the drawer's own animated scalar"
    # The drawer's scalar reaches the one declaration and nothing else in the
    # file - the size, the insets and the viewport may not learn it exists.
    occurrences = text.count("editDrawerProgress")
    assert occurrences == 1, \
        (f"GlobalStates.editDrawerProgress appears {occurrences} times in "
         f"Background.qml: the drawer's state may reach only the shift")
    viewport = declaration(text, "editViewport")
    assert "editShift" not in viewport and "drawerTravel" not in viewport, \
        "the geometry is a function of the drawer's WIDTH alone, never its state"
    # ...and the shift rides into the transform through the module's own
    # argument, so the exit's identity-at-zero holds for it too.
    transform = declaration(text, "editTransform")
    assert re.search(r"EditMode\.atProgress\([^)]*editShift", transform), \
        "the shift must go through atProgress, not be added to the matrix by hand"
    card = declaration(text, "editCard")
    assert "editShift" in card, \
        "the card the chrome frames must shift with the desktop it frames"


def test_the_mode_animates_on_exactly_one_scalar():
    # The desktop and the chrome that frames it are on two different layer
    # surfaces, and both build their geometry out of the progress. A second
    # Behavior anywhere is two numbers that must agree, and the frames where
    # they do not are the ones where the chrome frames a rectangle the desktop
    # is not at - which settles correctly and is therefore invisible at rest.
    behaviours = []
    for path in ROOT.rglob("*.qml"):
        if "/tests/" in str(path):
            continue
        if re.search(r"Behavior on editProgress|Behavior on editDrawerProgress",
                     path.read_text()):
            behaviours.append(str(path.relative_to(ROOT)))
    assert behaviours == ["GlobalStates.qml"], \
        f"the mode's progress is animated in more than one place: {behaviours}"
    assert re.search(r"readonly property real editProgress: GlobalStates\.editProgress",
                     read(BACKGROUND)), \
        "the desktop must read the shared scalar rather than deriving its own"
    assert "GlobalStates.editProgress" in read(CHROME_SURFACE), \
        "...and so must the chrome"


def test_the_snap_toggle_rides_the_settings_key_and_records_no_undo():
    # Maintainer, 2026-08-18: a toggle in the mode for edge snapping. It must
    # be the SAME key Settings offers and stage 10's detent rides -
    # `background.showSnapLines` - not a second one: the guide and the hold
    # travel together on that key, and two keys that must agree eventually
    # disagree. And it is a preference, not a committed mutation: no undo
    # entry, like the global widget lock. The write lives on the surface,
    # because that is where every store write the mode makes lives.
    content = code(CHROME_CONTENT)
    assert "signal snapToggleRequested()" in content, \
        "the chrome content no longer offers the snap toggle"
    button = re.search(r"id:\s*snapButton\n(.*?)\n\s*\}", content, re.S)
    assert button, "the toolbar has no snapButton"
    assert "toggled: Config.options.background.showSnapLines" in button.group(1), \
        "the snap toggle must read background.showSnapLines - the key the detent rides"
    assert "onClicked: root.snapToggleRequested()" in button.group(1), \
        "the snap toggle must signal the surface, not write the store from the chrome"
    surface = code(CHROME_SURFACE)
    assert re.search(r"onSnapToggleRequested:\s*Config\.options\.background\.showSnapLines\s*=\s*!Config\.options\.background\.showSnapLines",
                     surface), \
        "the surface must flip background.showSnapLines on the signal"
    handler = re.search(r"onSnapToggleRequested:[^\n]*", surface)
    assert handler and "editUndoPush" not in handler.group(0), \
        "the snap toggle is a preference and must not spend an undo entry"


def test_the_chrome_surface_is_static():
    # On a layer surface, position IS `margins`, so chrome animating into place
    # through them reconfigures the surface every frame - the create-map-destroy
    # loop BarPopupOverlay exists to avoid. The same four properties
    # lint_bar_popup_overlay_static.py pins there.
    text = read(CHROME_SURFACE)
    for edge in ("top", "bottom", "left", "right"):
        assert re.search(rf"^\s*{edge}: true\s*$", text, re.M), \
            f"the chrome surface does not anchor its {edge} edge"
    assert not re.search(r"^\s*margins\b", text, re.M), \
        "a margin on this surface is a reconfigure per frame"
    for prop in ("implicitWidth", "implicitHeight"):
        assert not re.search(rf"^\s*{prop}:", text, re.M), \
            f"the chrome surface sizes itself with {prop} instead of anchoring"
    assert re.search(r'^\s*color: "transparent"\s*$', text, re.M), \
        ("a window colour bound to a token latches the surface opaque and costs "
         "it its blur for the life of the process (deba3e3f6)")


def test_every_pixel_that_is_not_chrome_falls_through_to_the_desktop():
    # The failure this exists for is the whole point of the mode being usable:
    # a screen-sized Overlay surface that accepts input everywhere makes the
    # desktop underneath unclickable, and the desktop underneath is the thing
    # being edited.
    text = read(CHROME_SURFACE)
    mask = re.search(r"mask: Region \{(.*?)\n    \}", text, re.S)
    assert mask, "the chrome surface publishes no input mask at all"
    items = re.findall(r"item: (chrome\.\w+)", mask.group(1))
    assert items == ["chrome.toolbarItem", "chrome.tabBarItem", "chrome.drawerItem"], \
        f"the mask is not exactly the three chrome rects: {items}"
    # ...and nothing else on the surface may take a press. A screen-sized
    # MouseArea would be inside the mask's own hole and eat nothing, which is
    # exactly why it would survive review: it does nothing until the mask grows.
    # The DRAWER is the deliberate exception and is not in this sweep: its rows
    # are pointer areas by construction (a drag out of a clipped panel cannot
    # be a Button), and they sit inside the third mask rect - the reveal, which
    # is zero-width whenever the drawer is closed.
    for path in (CHROME_SURFACE, CHROME_CONTENT):
        body = read(path)
        assert "MouseArea" not in body, \
            f"{path.name} adds a pointer area to a surface whose mask is three rects"


def test_the_drawer_draws_its_rows_with_a_component_that_is_not_a_control():
    """The shared row must stay a plain item, or the drag out of the drawer dies.

    The drawer's five catalogues (desktop widgets, bar widgets, dock apps, the
    lock islands, the lock layout) all draw `CatalogueRow` now, and the same
    component draws every settings row and every widget-store card - so the
    tempting next edit is to fold the hover, the cursor and the click into it
    and let the call sites stop repeating themselves. That would take the
    desktop section's rows with it.

    Those rows are `MouseArea`s by construction (65602708e): a drag out of a
    clipped panel needs the implicit grab of the press to keep delivering
    events after the pointer has left the row, which is why they are the
    deliberate exception to the no-MouseArea sweep above. A shared row that
    is itself a control either eats the press before the MouseArea sees it or
    forces the drawer off the shared component again. Neither failure is
    loud: drag-to-place simply stops carrying anything out, on a gesture no
    test in this suite drives.
    """
    row = code(CATALOGUE_ROW)
    assert row.strip().startswith("import"), "CatalogueRow.qml is not QML"
    for spelling in ("MouseArea", "TapHandler", "DragHandler", "RippleButton",
                     "Button {", "signal clicked"):
        assert spelling not in row, (
            f"CatalogueRow grew a {spelling} - the drawer's drag-out needs the "
            f"press to stay with the call site's own MouseArea")
    # ...and the drawer still keeps the gesture, on the section that has one.
    drawer = code(DRAWER)
    assert "CatalogueRow {" in drawer, \
        "the drawer no longer draws its rows with the shared component"
    assert "delegate: MouseArea {" in drawer and "preventStealing: true" in drawer, \
        ("the desktop section's rows stopped being pointer areas - a Button "
         "does not keep delivering events once the pointer leaves the drawer")


def test_the_chrome_surface_leaves_the_keyboard_to_the_desktop():
    # Escape is answered by WidgetCanvas on the background surface, through
    # edit_mode.js's ladder. A chrome surface on Overlay taking OnDemand focus
    # sits in front of it and swallows the key - and the mode's own exit is
    # what stops working.
    assert re.search(r"WlrLayershell\.keyboardFocus:\s*WlrKeyboardFocus\.None",
                     read(CHROME_SURFACE)), \
        "the chrome surface must not take keyboard focus"


def test_the_chrome_surface_mints_a_namespace_and_declares_it_to_the_compositor():
    # A namespace absent from rules.lua falls through the catch-all
    # `ignore_alpha = 0.05`, under which a screen-sized surface's transparent
    # pixels clear the threshold and the compositor is asked to blur the entire
    # screen. Nothing logs it; it is loud only on the screen.
    text = read(CHROME_SURFACE)
    declared = re.search(r'WlrLayershell\.namespace:\s*"([^"]+)"', text)
    assert declared, "the chrome surface declares no namespace"
    namespace = declared.group(1)
    assert namespace not in ("quickshell:popup", "quickshell:background",
                             "quickshell:bar", "quickshell:dock"), \
        ("reusing a namespace inherits its ignore_alpha - BarPopupOverlay.qml "
         "records what that cost the tray menus")
    rules = RULES.read_text()
    assert re.search(rf'namespace = "{re.escape(namespace)}" \}}, ignore_alpha =',
                     rules), \
        f"{namespace} has no alpha threshold in rules.lua"
    # Above the bar and the dock, or the chrome renders underneath the two
    # surfaces the mode deliberately leaves at full size.
    assert re.search(r"WlrLayershell\.layer:\s*WlrLayer\.Overlay", text), \
        "the chrome must sit above the bar and the dock"


def test_the_chrome_stands_down_through_two_gates_of_its_own():
    # The same lesson as the desktop card's, on a surface this time: either gate
    # alone hides the chrome, so a frame comparison passes on a tree with one of
    # them deleted - and then the survivor gets deleted as redundant.
    scope = read(CHROME_SCOPE)
    assert re.search(r"active:\s*GlobalStates\.editMode \|\| GlobalStates\.editProgress > 0",
                     scope), \
        "the chrome surface must not exist while the mode is off"
    assert re.search(r"opacity:\s*GlobalStates\.editProgress", read(CHROME_SURFACE)), \
        "the chrome must be transparent while the mode is off"


def test_the_chrome_is_placed_off_the_desktops_own_rectangle():
    # One arithmetic for the desktop and the thing that frames it, so the
    # toolbar cannot end up a pixel off the card - the rule ClockDepthCutout is
    # one component for. It is re-derived rather than published across the
    # window boundary because every input is available on both sides; what it
    # may not do is invent a second geometry.
    surface = read(CHROME_SURFACE)
    assert "EditMode.cardRect(" in surface and "EditMode.viewportGeometry(" in surface, \
        "the chrome must take the desktop's rectangle from the module, not invent one"
    content = read(CHROME_CONTENT)
    assert re.search(r"property rect card:", content), \
        "the chrome content takes the desktop's rectangle"
    for axis in ("root.card.x", "root.card.y"):
        assert axis in content, f"the chrome does not place itself off {axis}"
    # ...and it moves with the progress rather than chasing it. A Behavior whose
    # target moves every frame restarts every frame and never ticks (b710ef731),
    # and everything here is a function of the one animated scalar already.
    declared = [line.strip() for line in content.splitlines()
                if "Behavior on" in line and not line.lstrip().startswith("*")
                and not line.lstrip().startswith("//")]
    assert declared == [], \
        f"the chrome's motion is the shrink's, and a Behavior on it would freeze: {declared}"


def test_the_drawer_is_the_modules_rect_and_the_drop_is_the_modules_arithmetic():
    """The drawer's geometry and the drop's mapping both come from edit_mode.js.

    The reveal is `drawerRect` - right edge pinned, width animating - because
    the surface's input mask tracks exactly x/y/width/height, so a closed
    drawer collapsing to zero width is what keeps a permanently-reachable
    full-height rect from eating clicks on whatever panel lives on that edge.
    And the drop goes screen -> canvas through `canvasPointFromScreen`, the
    inverse composed out of the same `atProgress` the desktop is drawn with: a
    hand-inverted copy here would be right at scale 1 and wrong everywhere
    else, which is the compensating-for-the-viewport failure this file already
    forbids by name.
    """
    surface = code(CHROME_SURFACE)
    assert "EditMode.drawerRect(" in surface, \
        "the drawer's reveal must come from the module, not be laid out by hand"
    assert "EditMode.canvasPointFromScreen(" in surface, \
        "the drop must invert the one transform through the module"
    assert "EditMode.dropPosition(" in surface, \
        "the drop's snap and clamp are the module's, not a second spelling"
    # The chrome frames the SHIFTED desktop: both the card it hands the content
    # and the travel itself ride the same scalar pair as the background's.
    assert "EditMode.drawerTravel(" in surface \
        and "GlobalStates.editDrawerProgress" in surface, \
        "the chrome must travel with the desktop the drawer pushes aside"
    # setPosition runs before the enable, or a newly enabled plugin mounts at
    # the store's default and then jumps to the drop - spec §8.3 places an
    # added widget the moment it is added.
    add = re.search(r"function addWidgetAt\([^)]*\)\s*\{(.*?)\n    \}", surface, re.S)
    assert add, "the surface no longer owns the drop"
    body = add.group(1)
    assert body.find("PluginState.setPosition(") != -1 \
        and body.find("enablePlugin(") != -1 \
        and body.find("PluginState.setPosition(") < body.find("enablePlugin("), \
        "the drop must write the position BEFORE enabling the plugin"

    # The drawer reports gestures and writes nothing: every store the mode
    # touches from this surface is written in the surface's own file, which is
    # what keeps lint_edit_mode_scope.py's question about writes answerable.
    drawer = code(DRAWER)
    assert "setNestedValue" not in drawer and "setPosition" not in drawer \
        and "setOption" not in drawer, \
        "the drawer writes a store; gestures are requests and the surface writes"
    for signal in ("addRequested", "toggleRequested"):
        assert re.search(rf"signal {signal}\(", drawer), \
            f"the drawer no longer raises {signal}"
    # The catalogue is PluginManager's, filtered by the surface vocabulary -
    # a hardcoded list here is the drift the BarWidgets stage exists to stop.
    assert "PluginManager.availablePlugins" in drawer, \
        "the drawer must be fed by PluginManager.availablePlugins"
    assert "pluginSurfaces" in drawer and "desktop-widget" in drawer, \
        "the drawer must filter by the declared surface capability"


def test_the_mode_has_one_way_in_and_the_toolbar_owns_the_way_out():
    # Two controls that disagree about what they do is the failure; two that
    # agree is merely redundant. This picks the first: the desktop menu enters,
    # the toolbar's Done leaves, and neither is the other's second opinion.
    menu = read(DESKTOP_MENU)
    writes = re.findall(r"GlobalStates\.editMode = ([^\n]+)", menu)
    assert writes == ["true"], \
        f"the desktop menu is no longer only the way in: {writes}"
    # `rowVisible`, not `visible`. A GroupedList row hidden the second way keeps
    # its plate - a row-height band of the group's own background with nothing
    # in it, which is what this menu grew between Widgets and DropShelf for the
    # whole life of the mode. GroupedList.qml says why the widget cannot simply
    # mirror `visible`; this pins the call site that reported it.
    assert re.search(r"property bool rowVisible:\s*!GlobalStates\.editMode", menu), \
        "the Edit layout row must not sit in the menu doing nothing while the mode is on"
    assert not re.search(r"^\s*visible:\s*!GlobalStates\.editMode", menu, re.M), \
        "a GroupedList row hidden with `visible` leaves an empty plate behind"
    assert re.search(r"GlobalStates\.editMode = false", read(CHROME_SURFACE)), \
        "the toolbar's Done is the mode's exit"
    # Leaving takes the gesture and the selection with it: Done means stop, and
    # a selection halo left on the desktop has no visible way to be cleared.
    assert re.search(r"onEditModeChanged:[^\n]*clearSelection", read(CANVAS)), \
        "leaving the mode leaves a selection behind"


def test_the_bar_and_the_dock_have_exactly_one_answer_for_where_they_are():
    """The insets are derived once, and both surfaces read that one object.

    Everything else about the mode's geometry is re-derived on the background
    surface and on the chrome surface, because every input is an `Appearance`
    token and the same screen. These four numbers are not: they come from
    `Config.options.bar.*`, `Config.options.dock.*` and `dock_geometry.js`, so a
    second file working them out is a second answer to where the dock is - the
    thing `test_dock_position_contract.py` exists to prevent for the dock's own
    tree. The failure is silent in the worst way: two surfaces that disagree
    frame a rectangle the desktop is not at, and only on the machine whose bar
    is the height that makes them differ.
    """
    insets = code(INSETS)
    assert re.search(r"^pragma Singleton", insets, re.M), \
        "the insets are one object, not a component each surface instantiates"
    assert "DockGeometry.thickness(" in insets, \
        "the dock's thickness comes from the dock's own module"
    # The bar's overloaded pair and the dock's stored edge both become an edge
    # NAME in dock_geometry.js and nowhere else - `test_dock_position_contract.py`
    # owns that rule and caught this file re-deriving both on its first run.
    assert "DockGeometry.barEdge(" in insets and "DockGeometry.normalizedEdge(" in insets, \
        "an edge name is derived in the dock's module, not spelled out again"

    for path in (BACKGROUND, CHROME_SURFACE):
        text = code(path)
        assert "EditModeInsets.insetsFor(" in text, \
            f"{path.name} must take the insets from the one derivation"
        for term in ("insetTop:", "insetBottom:", "insetLeft:", "insetRight:"):
            assert term in text, f"{path.name} drops {term} on the way in"
        assert "chromeThickness: Appearance.sizes.toolbarHeight" in text, \
            f"{path.name} must reserve the toolbar's own height, not a literal"

    # Nothing else in the mode may reach for either panel's configuration. A
    # file that reads `dock.edge` to decide where the chrome goes is the second
    # derivation this exists to stop, whatever it then does with it.
    for path in PARTICIPANTS + [CARD, LOOK_PROBE]:
        if path is BACKGROUND:
            continue
        text = code(path)
        for key in ("Config.options.dock", "Config.options?.dock",
                    "Config.options.bar.bottom", "Config.options?.bar.bottom"):
            assert key not in text, \
                f"{path.name} works out where a panel is instead of asking EditModeInsets"


def test_the_reservation_does_not_move_while_the_mode_is_on():
    """A viewport that changes size mid-edit rescales every widget under the
    cursor and hands every Behavior carrying the box a moving target
    (b710ef731). So the insets are a function of CONFIGURATION - never of
    auto-hide, hover reveal, `barOpen`, or a fullscreen window dropping the
    dock's exclusive zone, all of which move while the user is editing.

    It is the same decision `edit_mode.js` makes about the drawer's width, and
    the same reason: reserve the space whether or not the thing is in it.
    """
    insets = code(INSETS)
    for moving in ("GlobalStates.barOpen", "hoverToReveal", "pinnedOnStartup",
                   "containsMouse", "fullscreen", "ToplevelManager",
                   "autoHide.enable"):
        assert moving not in insets, \
            f"the reservation follows {moving}, which moves while the mode is on"
    # `viewportGeometry` has no input for the drawer's open state either, and
    # this is the check that keeps the two consistent as stage 5 lands.
    assert "drawerOpen" not in code(MODULE), \
        "the geometry must not learn whether the drawer is open"


def test_the_chrome_is_placed_between_the_card_and_the_usable_area():
    """The band the toolbar sits in is the gap between the two rectangles, not
    between the card and the screen.

    Placed against the surface's own height, the chrome clears the card and
    lands on whatever is on that edge - which is what stage 4 shipped: the
    toolbar over the bar's widgets and the tab bar over the dock's. Both
    rectangles come from the module and both are functions of the same
    progress, so the placement carries no motion of its own either.
    """
    content = code(CHROME_CONTENT)
    assert re.search(r"property rect area:", content), \
        "the chrome content takes the usable area as well as the card"
    for term in ("root.area.y", "root.area.height"):
        assert term in content, f"the chrome does not place itself off {term}"
    # The screen's own edges are exactly what it may no longer measure from.
    assert not re.search(r"\(root\.height\s*-\s*root\.card", content), \
        "the tab bar is placed against the screen's bottom edge, not the usable area's"
    assert "EditMode.areaRect(" in code(CHROME_SURFACE), \
        "the usable area must come from the module, not be rebuilt on the surface"


def test_the_cards_edge_is_one_tone_and_nothing_is_drawn_inside_the_card():
    """The edge is a catch on one band outside the card, and there is nothing
    else on the boundary.

    Two lines have sat inside the card in turn and both were the same object. A
    1px `colLayer0Border` outline, which measured as a notch - up to 70/255
    below the lower of the two bright bands either side of it - and went in
    1df616e62. Then a 1px `colGlassSpecular` highlight at 0.16, which measured
    as the BRIGHTEST thing on the boundary on three edges out of four, +41
    levels over a wallpaper at 105. Anything inside the card cannot ride
    `surround`'s mask, so it is a uniform border by construction, at one
    strength round the whole perimeter, and a border of even thickness is what
    "edit mode's layout having this thick border" names.

    The shade band outside is held to the same rule from the other side: what
    darkens outside the card is `colShadow`, already drawn there by
    `StyledRectangularShadow`, softly and from the same lamp. A second darkening
    is a hard copy of the soft one under it, which is the other two of the five
    drawn pixels the edge used to occupy.

    `test_edit_mode_chrome.py` scores the profile in pixels; this is the source
    half, because both of these come back as "every floating surface in this
    shell carries one". docs/M3_GUIDELINES.md §1 is what licenses their absence
    rather than what they are traded against: "visible borders are not required
    for every surface", and the job it gives an outline - defining edges against
    complex backgrounds - belongs here to the shadow and to the catch.
    """
    card = code(CARD)
    assert "colLayer0Border" not in card, \
        "the card's edge is a catch; an outline through it is a seam"
    assert "colGlassShade" not in card, \
        ("the darkening outside the card is StyledRectangularShadow's; a shade "
         "band beside it is a hard copy of the soft one underneath")
    # Every tone the edge is drawn in has to be a child of `surround`, whose
    # mask cuts it back to the band outside the card. A `border.width` is the
    # only way to paint a line at the card's edge from outside that item, which
    # is exactly why both of the lines that have sat there were written as one.
    assert "border.width" not in card, \
        "nothing may be drawn inside the card: a border there is the outline again"
    # ...and the roll-off is the corner's, not a number someone picked. A stop
    # at a literal fraction is a rim that is bright right round the bend, which
    # is a stroke however bright it is - the thing the file's own comment
    # forbids.
    roll_off = declaration(card, "edgeRollOff")
    assert "cardRadius" in roll_off, \
        f"the catch's roll-off must be expressed against the corner radius: {roll_off!r}"
    assert card.count("root.edgeRollOff") >= 2, \
        "the roll-off must bound the crest at both ends of the flank"


def test_the_cards_edge_is_a_catch_rather_than_a_rim():
    """One pixel wide, and the flank is a fraction of the top rather than a bit
    less than it.

    This is the rule the previous edge passed on and still read as a border. Its
    specular was already non-uniform - 0.46 along the top against 0.26 down the
    flank - and 0.26 of white on a 2px band all the way round a 3872px card is a
    rim at 57% of full strength, which is a stroke a shade fainter rather than a
    catch. Glass shows a bright catch where the light hits it and almost nothing
    along the rest, and what carries its presence is the shadow around it.

    So the two numbers that decide whether this is an edge or a border are the
    band's WIDTH and the RATIO between its top and its flank, and both are
    asserted here rather than left to whoever tunes a stop next. The pixel half
    scores what these produce on screen; a source check is what stops a stop
    being nudged back up one at a time.
    """
    card = code(CARD)
    width = declaration(card, "edgeSpecularWidth")
    assert "borderWidth.standard" in width, \
        (f"the catch is one pixel: a wider band is a rim whatever its alpha is "
         f"({width!r})")

    stops = [float(v) for v in
             re.findall(r"colGlassSpecular,\s*([0-9.]+)\s*\)", card)]
    assert len(stops) == 4, \
        f"expected four gradient stops on the catch, found {stops}"
    top, arc_top, arc_bottom, bottom = stops
    assert arc_top == arc_bottom, \
        f"the flank is one value between the two corner arcs, not a ramp: {stops}"
    assert arc_top <= top / 4, \
        (f"the flank is {arc_top} against a top of {top}: a rim at a fraction "
         f"under the top is still a rim")
    assert arc_top < bottom < top, \
        (f"the bottom is a bounce - above the flank and below the top - not a "
         f"second catch: {stops}")


def test_the_right_click_is_the_menu_in_the_mode_and_the_lock_outside_it():
    # One click, two meanings, decided by the mode (spec 4.1's table changes
    # only the in-mode column). Both halves are pinned because each can rot
    # alone: losing the in-mode branch brings back a SILENT lock write - the
    # mode suppresses the global lock, so flipping it from inside has no
    # visible effect until the mode ends - and losing the outside branch takes
    # away the lock's one sanctioned quick gesture.
    widget = code(WIDGET)
    handler = re.search(r"onClicked:\s*\(mouse\)\s*=>\s*\{(.*?)\n    \}", widget, re.S)
    assert handler, "AbstractWidget no longer answers the click"
    body = handler.group(1)
    menu = re.search(r"canvas\.editMode\s*===\s*true", body)
    lock = re.search(r"Config\.options\.background\.widgetsLocked\s*=(?!=)", body)
    assert menu and "contextMenuRequested" in body, \
        "in the mode the right-click must raise the widget's menu"
    assert lock, "outside the mode the right-click must still toggle the lock"
    assert menu.start() < lock.start(), \
        ("the menu branch must be resolved first, or the in-mode click writes "
         "the lock as well as opening the menu")
    # The subclass that answers the request maps the point through Qt's own
    # transform chain - the scene mapping - never by multiplying a viewport
    # scale in by hand (the compensation the sweep above already forbids by
    # name; this is the positive half).
    plugin = code(PLUGIN_WIDGET)
    request = re.search(r"onContextMenuRequested:\s*\(atX, atY\)\s*=>\s*\{(.*?)\n    \}",
                        plugin, re.S)
    assert request, "PluginWidget no longer answers the menu request"
    assert "mapToItem(null" in request.group(1), \
        "the menu's anchor must go through the widget's own transform chain"
    for field in ("editWidgetMenuPluginId", "editWidgetMenuScreenName",
                  "editWidgetMenuX", "editWidgetMenuY", "editWidgetMenuOpen"):
        assert f"GlobalStates.{field}" in request.group(1), \
            f"the menu request no longer writes {field}"


def test_a_destroyed_widget_vacates_the_menu_it_opened():
    # The BarContent.filterLayout shape: disabling a plugin (the menu's own
    # Remove included) destroys the widget while the menu still points at it,
    # and a stranded menu offers Remove/Pin/Size about nothing. The declaring
    # object vacates from Component.onDestruction, keyed on the id AND the
    # screen - every monitor holds an instance of the plugin, and only the one
    # the menu was opened on may close it.
    plugin = code(PLUGIN_WIDGET)
    vacate = re.search(
        r"Component\.onDestruction:\s*\{(.*?)\n    \}", plugin, re.S)
    assert vacate, "PluginWidget no longer vacates on destruction"
    body = vacate.group(1)
    assert "editWidgetMenuOpen = false" in body, "the vacate no longer closes the menu"
    assert "editWidgetMenuPluginId" in body and "editWidgetMenuScreenName" in body, \
        "the vacate must match both the id and the screen before closing"


def test_the_size_affordance_indexes_offered_spans_and_never_a_pixel():
    # Spec 5's rule, mechanized (11.2): the host can only ever assign an
    # offered span, so the menu's Size is a stepper over offeredGridSizes and
    # the tempting way to build it - a handle over pixels - must be
    # unreachable. A widget offering one span gets no row at all (omitted, not
    # disabled), and one that declined `grid` (calendar, world-clock,
    # custom-image) offers zero, so its own handles keep the size they chose.
    content = code(MENU_CONTENT)
    assert "GridSizes.offeredSizes(" in content, \
        "the menu no longer takes its spans from the offered list"
    assert "GridSizes.steppedSize(" in content, \
        "the step must come from the module, where tst_grid_sizes owns the walk"
    assert re.search(
        r'setGridSize\(id, screen, GridSizes\.formatSize\(next\), surface\)',
        content), \
        "the size write must be the stepped offered span and nothing else"
    # No pointer anywhere near the size: the card's rows are buttons, and a
    # MouseArea is how a pixel delta would arrive.
    assert "MouseArea" not in content, \
        "the menu card grew a pointer area - a size handle starts this way"
    assert "onPositionChanged" not in content
    # No second copy of the grip's tension walk either.
    assert "previewGridResize" not in content and "BREAK_PX" not in content, \
        "the menu re-implements the grip instead of stepping the offered list"
    # The row comes and goes with the offered count, through GroupedList's own
    # mechanism - `visible` would leave an empty plate (b949bf24a).
    assert re.search(r"rowVisible:\s*root\.offeredSizes\.length > 1", content), \
        "a single-span widget must get no Size row, via rowVisible"


def test_the_pin_is_one_writer_with_two_call_sites_and_a_bound_state():
    # Spec 9's first deliberate edge case: a "Widget behaviour" toggle that is
    # about placement. The write goes through the one existing writer
    # (PluginState.setOption), and the drawn state is a BINDING on the stored
    # value with the host's own manifest seed - never local state, which is the
    # ConfigSwitch lesson: a row holding its own flag detaches from the store
    # on the first external write and then lies about it.
    content = code(MENU_CONTENT)
    pinned = declaration(content, "pinned")
    assert pinned, "the pin row no longer binds its state"
    assert "PluginState.option(" in pinned and "positionLocked" in pinned, \
        "the pin state must be read from the store"
    assert "desktopWidget?.locked === true" in pinned, \
        "the pin state must be seeded the way PluginWidget seeds it"
    assert re.search(
        r'PluginState\.setOption\([^)]*"positionLocked",\s*!root\.pinned\)', content), \
        "the pin click must flip the stored value at its source"


def test_remove_is_presence_through_the_one_spelling():
    # Presence on the surface is one list and one write: the menu's Remove,
    # the drawer's toggle and Settings > Widgets all mutate plugins.enabled,
    # and the two edit-mode call sites share EditMode.enabledWithout so they
    # cannot disagree about order or duplicates.
    content = code(MENU_CONTENT)
    assert 'Config.setNestedValue("plugins.enabled"' in content, \
        "the menu's Remove no longer writes presence"
    assert "EditMode.enabledWithout(" in content, \
        "the menu spells its own removal loop instead of the shared one"
    assert "EditMode.enabledWithout(" in code(CHROME_SURFACE), \
        "the drawer's toggle left the shared spelling"


def test_the_menu_window_is_the_desktop_menus_shape():
    # A transient full-screen Overlay window that exists only while open, on
    # the reused quickshell:desktopMenu namespace - the same kind of surface as
    # the desktop's own menu, under the same compositor rules. A menu on the
    # background surface would sit under the bar; a fourth mask region on the
    # chrome surface could never dismiss on an outside click, because every
    # pixel outside the chrome's rects falls through to the desktop.
    menu = code(MENU)
    assert 'WlrLayershell.namespace: "quickshell:desktopMenu"' in menu, \
        "the menu window left the desktop menu's namespace"
    assert re.search(r'color:\s*"transparent"', menu), \
        "the window's clear colour must stay a literal (deba3e3f6)"
    assert re.search(r"active:\s*GlobalStates\.editWidgetMenuOpen", menu), \
        "the window must exist only while the menu is open"
    assert re.search(r"onClicked:\s*GlobalStates\.editWidgetMenuOpen = false", menu), \
        "a click outside the card must dismiss the menu"
    assert "WlrLayershell.layer: WlrLayer.Overlay" in menu, \
        "the menu must map above the mode's chrome, or it opens under the toolbar"
    # Explicit, not defaulted: this Overlay surface must not hold the keyboard,
    # because the menu's own Escape rung is answered on the background surface
    # - the same pin the chrome surface carries, for the same reason.
    assert "WlrLayershell.keyboardFocus: WlrKeyboardFocus.None" in menu, \
        "the menu window must decline the keyboard the Escape ladder needs"
    # The click-eater under the card: without it a click on the card's title
    # row or plate padding falls through to the closer and dismisses the menu -
    # and no harness can see it, because no harness can build this window.
    eater = re.search(
        r"MouseArea\s*\{\s*x:\s*card\.x\s*y:\s*card\.y\s*width:\s*card\.width\s*"
        r"height:\s*card\.height\s*acceptedButtons:\s*Qt\.AllButtons", menu)
    assert eater, "a click ON the card must not read as a click away from it"


def test_the_menu_does_not_outlive_the_mode():
    states = code(GLOBAL_STATES)
    handler = re.search(r"onEditModeChanged:\s*\{(.*?)\n    \}", states, re.S)
    assert handler, "GlobalStates no longer answers the mode ending"
    assert "editWidgetMenuOpen = false" in handler.group(1), \
        ("leaving the mode must close the menu - one left open would greet the "
         "next entry pointing at wherever a widget used to be")


def test_the_tab_is_a_string_beside_the_mode_and_dies_with_it():
    # Spec §1.4: the Lockscreen tab is a FILTER on the viewport, not a mode -
    # one GlobalStates.editMode, and the tab a string beside it. Session state
    # for the same reason the mode is, and reset on exit so the next entry
    # opens on the Desktop tab rather than mid-preview.
    states = code(GLOBAL_STATES)
    assert re.search(r"property string editTab:\s*EditMode\.DESKTOP_TAB", states), \
        ("GlobalStates must declare the tab, defaulted through the module's "
         "constant rather than a second spelling of the string")
    assert "editTab" not in read(CONFIG), \
        "a persisted tab is a shell that restarts into the Lockscreen preview"
    handler = re.search(r"onEditModeChanged:\s*\{(.*?)\n    \}", states, re.S)
    assert handler and "editTab = EditMode.DESKTOP_TAB" in handler.group(1), \
        ("leaving the mode must return the tab to Desktop - a tab left latched "
         "would greet the next entry already filtered to the lock screen")


# "The lock's look is on screen" - either spelled out, or read off the one
# derivation in GlobalStates. The disjunction was written at six sites and a
# seventh (the palette) was missed, so the property exists and the sites read
# it; the check below pins its DEFINITION, and every site may use either form.
LOCK_LOOK = (r"(?:GlobalStates\.lockLookActive"
             r"|GlobalStates\.screenLocked\s*\n?\s*\|\|\s*"
             r"GlobalStates\.editLockPreview)")


def test_the_viewport_draws_its_locked_inputs_on_the_lockscreen_tab():
    # Spec §4.3: the tab switches the viewport's wallpaper and blur to their
    # locked inputs - a gate change on things Background.qml already draws,
    # with the preview joining the session lock in each gate rather than a
    # second copy of any layer. Each binding is named individually because a
    # missing term here is silent: the tab simply previews the wrong
    # wallpaper, on machines that configured a lock wallpaper, which is not
    # every machine.
    states = code(GLOBAL_STATES)
    look = declaration(states, "lockLookActive")
    assert look and re.search(r"screenLocked\s*\|\|\s*"
                              r"root\.editLockPreview", look), \
        ("GlobalStates.lockLookActive must stay `screenLocked || "
         "editLockPreview` - every gate below reads it, so a narrowed "
         "definition silently un-filters all of them at once")
    background = code(BACKGROUND)
    for name in ("effectiveWallpaperPath", "weProjectPath"):
        value = declaration(background, name)
        assert value, f"Background no longer declares {name}"
        assert re.search(LOCK_LOOK, value), \
            f"{name} does not take the lock preview's term"
    lock_wall = declaration(background, "lockWallShown")
    assert lock_wall and re.search(LOCK_LOOK, lock_wall), \
        "lockWallShown does not take the lock preview's term"
    blur = re.search(r"id:\s*blurLoader\n(.*?)sourceComponent:", background, re.S)
    assert blur, "the lock blur loader is gone"
    assert re.search(r"lockLook:\s*" + LOCK_LOOK, blur.group(1)), \
        "the lock blur's lockLook must cover the preview"
    assert re.search(r"active:.*lockLook", blur.group(1)), \
        "the lock blur must be active for the locked look"
    # And the widget filter: the tab shows the widgets the lock screen will.
    widget = code(BACKGROUND_WIDGET)
    # One expression asks WHICH surface is on screen and then that surface's
    # own filter, so a widget picked for the lock alone cannot leak onto the
    # desktop and one the desktop shows cannot leak onto the lock.
    assert re.search(r"opacity:\s*\(" + LOCK_LOOK
                     + r"\s*\?\s*visibleWhenLocked\s*:\s*visibleOnDesktop\)",
                     widget), \
        "AbstractBackgroundWidget's lock filter does not cover the preview"
    # The palette is a locked input too, and the one that was missed: the tab
    # switched every SOURCE and left the colours the desktop's.
    theme = code(THEME_LOADER)
    gate = declaration(theme, "lockThemeActive")
    assert gate and re.search(LOCK_LOOK, gate), \
        ("MaterialThemeLoader.lockThemeActive must cover the preview, or the "
         "Lockscreen tab shows the lock's wallpaper under the desktop's "
         "palette")
    appearance = code(APPEARANCE)
    quantizer = re.search(r"id:\s*wallColorQuant\n(.*?)\n    \}", appearance, re.S)
    assert quantizer and re.search(LOCK_LOOK, quantizer.group(1)), \
        ("Appearance's wallpaper quantizer must cover the preview - it is "
         "what the shell's transparency is derived from")


def test_the_islands_ride_the_edit_transform_above_the_widgets():
    # The islands host is a FOURTH carrier of the one edit matrix (wallpaper
    # viewport, widget canvas, clock depth layer, islands) - the count is
    # pinned so a fifth copy is a deliberate change here, not a drift. It sits
    # at z 4: above the widget canvas (z 2), because the real session lock
    # surface draws over the desktop widgets, and above the depth layer (z 3),
    # which stands down for the mode anyway.
    background = code(BACKGROUND)
    host = re.search(r"id:\s*lockPreviewIslands\n(.*?)sourceComponent:",
                     background, re.S)
    assert host, "Background.qml no longer declares the islands host"
    body = host.group(1)
    assert "GlobalStates.editLockPreview" in body, \
        "the islands host must be gated on the one preview derivation"
    assert re.search(r"z:\s*4", body), "the islands must draw above the widgets"
    assert re.search(r"transform:\s*Matrix4x4\s*\{\s*matrix:\s*bgRoot\.editMatrix\s*\}",
                     body), "the islands must take the same edit transform"
    assert "suppressContents" in body, \
        ("the islands need their own copy of the fullscreen gate, like every "
         "other sibling that left the viewport")


def test_island_visibility_is_presence_through_literal_paths():
    # Spec §12 stage 9: island VISIBILITY is editable in the mode, and the
    # three lock.show* booleans are presence-on-a-surface - already inside
    # §7.1's allowlist (`lock.show*` in lint_edit_mode_scope.py) since the
    # allowlist was written. The drawer offers them as a Lock section and
    # still writes nothing (its writes-nothing rule is held by the bar/dock
    # contract); the chrome surface makes the three writes, each at a literal
    # path, because an allowlist reachable through a computed key is not an
    # allowlist.
    drawer = code(DRAWER)
    assert re.search(r'section === "lock"', drawer), \
        "the drawer no longer offers the Lock section"
    assert "lockToggleRequested" in drawer, \
        "the drawer's lock rows must raise a signal, not write"
    for key in ("showToolbars", "showMedia", "showWidgets"):
        assert key in drawer, f"the Lock section no longer offers {key}"
    surface = code(CHROME_SURFACE)
    for key in ("showToolbars", "showMedia", "showWidgets"):
        assert re.search(
            rf"Config\.options\.lock\.{key}\s*=\s*!Config\.options\.lock\.{key}",
            surface), \
            f"the surface must flip lock.{key} at its literal path"
    assert not re.search(r"Config\.options\.lock\[", surface + drawer), \
        "a computed lock key routes around the allowlist"


def test_the_lock_section_picks_which_widgets_the_lock_screen_shows():
    # The other half of the fork spec §4.3 chose for the layout: presence
    # inherits the desktop's enabled set until the first pick on this tab, and
    # the drawer says which of the two states it is in. Three things about the
    # arrangement are checked because each is silent when wrong.
    drawer = code(DRAWER)
    # The picker lives UNDER the master gate, in both senses: the rows are
    # built only while `lock.showWidgets` is on, because with the lock showing
    # no widgets at all they would be controls that change nothing.
    rows = declaration(drawer, "lockWidgetRows")
    assert rows and "Config.options.lock.showWidgets" in rows, \
        ("the per-widget rows must be gated on the master switch, or the Lock "
         "section offers a picker for a lock screen that shows no widgets")
    assert "desktopManifests" in rows, \
        ("the picker must offer the same catalogue the Widgets section does - "
         "a second filter is a second answer to what a desktop widget is")
    # One list, two kinds of row, and the delegate has to route the click by
    # kind: an island writes a lock.show* boolean and a widget writes the
    # choice, and the two go to different signals.
    assert re.search(r"lockRow\.isWidget\s*\n?\s*\?\s*root\.lockWidgetToggleRequested",
                     drawer), \
        "a widget row's click must raise the per-widget signal, not the island one"
    # And the master gate's own caption stops claiming "every" once it is not.
    assert "Show the widgets picked below while locked" in drawer, \
        ("the Desktop widgets row must say which state the choice is in, or "
         "'every' goes on describing a set the picked rows have replaced")
    surface = code(CHROME_SURFACE)
    assert "onLockWidgetToggleRequested" in surface, \
        "the surface does not answer the drawer's per-widget signal"
    assert "onLockPresenceResetRequested" in surface, \
        "the surface does not answer the drawer's re-link"


def test_the_clock_previews_its_locked_look_through_one_derivation():
    # The clock is THE lock-screen widget - its locked style, its centring,
    # its "show only when locked" presence and its Locked caption are all
    # keyed on the real lock. A Lockscreen tab that previews none of them is
    # a preview of a different lock screen, so all four ride one local
    # `lockLook` derivation; four separate `screenLocked || editLockPreview`
    # spellings would be four chances for one of them to lose a term.
    clock = code(ROOT / "modules/common/plugins/bundled/clock/Widget.qml")
    assert re.search(r"readonly property bool lockLook:\s*GlobalStates\.screenLocked"
                     r"\s*\n?\s*\|\|\s*GlobalStates\.editLockPreview", clock), \
        "the clock no longer derives its locked look once"
    for name, pattern in (
            ("forceCenter", r"forceCenter:\s*root\.lockLook"),
            ("clockStyle", r"clockStyle:\s*root\.lockLook"),
            ("shouldShow", r"shouldShow:\s*!root\.showOnlyWhenLocked\s*\|\|\s*root\.lockLook"),
            ("the Locked caption", r"shown:\s*root\.lockLook\s*&&\s*Config\.options\.lock\.showLockedText")):
        assert re.search(pattern, clock), \
            f"the clock's {name} does not follow the locked look"


def test_the_tab_bar_offers_both_tabs_and_follows_the_state():
    # The tab bar is the pointer's way onto the Lockscreen tab and the state
    # is `GlobalStates.editTab`, so the two must not hold hands loosely: the
    # widget's index follows any external tab write (the Escape ladder's
    # return to Desktop, the mode's exit reset), and every index change -
    # including the tab bar's own wheel shortcut, which writes the index
    # without going through a button - writes the state back. Both directions
    # are imperative-to-imperative on purpose: ToolbarTabBar's wheel handler
    # writes its inner index directly, which would destroy a binding placed
    # on it and leave the indicator and the viewport disagreeing.
    text = code(CHROME_CONTENT)
    tabs = re.search(r"tabButtonList:\s*\[(.*?)\]", text, re.S)
    assert tabs, "the chrome no longer declares its tab list"
    names = re.findall(r"name:\s*Translation\.tr\(\"(\w+)\"\)", tabs.group(1))
    assert names == ["Desktop", "Lockscreen"], \
        f"expected the Desktop and Lockscreen tabs in that order, found {names}"
    assert re.search(
        r"onCurrentIndexChanged:\s*GlobalStates\.editTab\s*=\s*EditMode\.tabAt",
        text), \
        ("an index change must write the tab state through the module's "
         "mapping, or the wheel desyncs them")
    assert "EditMode.tabIndex(GlobalStates.editTab)" in text, \
        "the state-to-index direction must go through the module's mapping too"
    assert re.search(r"function onEditTabChanged\(\)", text), \
        ("the tab bar must follow an external tab write - Escape's return to "
         "Desktop moves the state, and an indicator left behind frames a "
         "viewport showing the other tab")


def test_the_lockscreen_preview_is_one_derivation():
    # "The viewport is showing the lock screen's inputs" is asked by the
    # wallpaper, the blur, the widget filter, the islands host, both bars and
    # the dock. One readonly derivation in GlobalStates answers all of them;
    # a second `editTab === ...` comparison anywhere else is a second answer
    # to one question, and the two disagree the first time either moves.
    states = code(GLOBAL_STATES)
    assert re.search(
        r"readonly property bool editLockPreview:\s*root\.editMode\s*&&\s*"
        r"root\.editTab === EditMode\.LOCKSCREEN_TAB", states), \
        "GlobalStates no longer derives the preview from the mode and the tab"
    # Tree-wide, not a participant list: the consumers of the preview flag
    # (both bars, the dock, the clock plugin) live outside the mode's own
    # files, and the fifth file to grow an `editTab ===` comparison will be
    # too. `tests/` is excluded - the tst pins the literal against the
    # constant on purpose - and so are the rule's two named homes:
    # edit_mode.js for the literal, GlobalStates.qml for the comparison.
    swept = 0
    for path in sorted(list(ROOT.rglob("*.qml")) + list(ROOT.rglob("*.js"))):
        if (ROOT / "tests") in path.parents:
            continue
        # The runtime harnesses live at the root but are tests: their tab
        # comparisons are assertions about the state, not derivations from it.
        if path.name.endswith("RuntimeTest.qml") or path.name.endswith("Probe.qml"):
            continue
        text = code(path)
        swept += 1
        if path != MODULE:
            assert '"lockscreen"' not in text and "'lockscreen'" not in text, \
                f"{path} spells the Lockscreen tab as a literal"
        if path == GLOBAL_STATES:
            continue
        assert not re.search(r"editTab\s*===", text), \
            (f"{path} compares the tab itself - read "
             f"GlobalStates.editLockPreview instead")
        for match in re.finditer(r"(?<![.\w])editLockPreview\b", text):
            line = text[text.rfind("\n", 0, match.start()) + 1:
                        text.find("\n", match.start())]
            assert "GlobalStates.editLockPreview" in line, \
                f"{path}: a second source for the preview: {line.strip()}"
    assert swept > 400, f"the tree sweep found only {swept} files"


def test_the_undo_stack_is_the_modules_arithmetic_and_records_only_in_the_mode():
    # Spec §7.3. The stack lives in GlobalStates but its bound and its order
    # are edit_mode.js's tst-covered functions - a shift or a limit open-coded
    # in the singleton would be a second copy of arithmetic the tests cannot
    # see. And the push is gated on the mode: the same gestures commit all day
    # with the mode off, and Ctrl+Z inside the mode reversing a drag made
    # hours earlier would be undo reaching past the editor whose affordance
    # it is.
    states = code(GLOBAL_STATES)
    assert re.search(
        r"function editUndoPush\(entry\)\s*\{\s*"
        r"if \(!root\.editMode\) return;\s*"
        r"if \(root\.editUndoBatch !== null\)",
        states), "editUndoPush no longer gates on the mode before anything else"
    assert "root.editUndoStack = EditMode.undoPush(root.editUndoStack, entry)" in states, \
        "editUndoPush no longer defers to the module's arithmetic"
    # A gesture that commits several mutations folds them into one entry: the
    # batch is opened by the canvas at a group release and closed a turn
    # later, or the leader's entry sits on top and the first Ctrl+Z deforms
    # the cluster.
    canvas_text = code(CANVAS)
    assert "GlobalStates.editUndoBeginBatch()" in canvas_text \
        and "Qt.callLater(GlobalStates.editUndoEndBatch)" in canvas_text, \
        "a group release no longer batches its members into one entry"
    assert "EditMode.undoPop(root.editUndoStack)" in states, \
        "editUndo no longer pops through the module"
    module = code(MODULE)
    for name in ("UNDO_LIMIT", "function undoPush", "function undoPop",
                 "function listCopy"):
        assert name in module, f"edit_mode.js lost {name}"


def test_ctrl_z_lives_on_the_canvas_and_leaves_the_ladder_alone():
    # Probe 4's measured answer is what licenses the wiring: the BACKGROUND
    # surface's canvas receives compositor keys under OnDemand focus, so
    # Ctrl+Z is answered there - gated on the mode, through GlobalStates'
    # one undo entry point, and accepted so nothing beneath re-answers it.
    # The chrome surface stays keyboard-None (its own check above), and the
    # Escape ladder is a different rung entirely: undo reverses the last
    # COMMITTED mutation, Escape cancels the gesture still in flight.
    canvas = code(CANVAS)
    start = canvas.find("Keys.onPressed")
    assert start != -1, "the canvas lost its key handler"
    handler = canvas[start:canvas.find("Keys.onEscapePressed", start)]
    assert "if (!root.editMode) return" in handler, \
        "Ctrl+Z is no longer gated on the mode"
    assert "Qt.Key_Z" in handler and "Qt.ControlModifier" in handler, \
        "the canvas no longer answers Ctrl+Z"
    assert "GlobalStates.editUndo()" in handler, \
        "Ctrl+Z stopped going through the one undo entry point"
    assert "event.accepted = true" in handler, \
        "an unaccepted Ctrl+Z falls through to whatever sits beneath"
    assert re.search(r"Keys\.onEscapePressed", canvas), \
        "the Escape ladder left the canvas"


def test_every_committed_mutation_records_exactly_its_entries():
    # Spec §7.3's five kinds of committed mutation, as push counts per file.
    # Exact rather than at-least in both directions: a site that stops
    # pushing is a mutation undo silently forgot, and a NEW push is a new
    # licence that belongs in this table on review. The closures' discipline
    # (only singletons and captured data, literal store paths) is stated at
    # each site; what a count can hold is that the sites exist at all.
    expected = {
        PLUGIN_WIDGET: 2,      # a drag's release; a span commit (grip + Size row path)
        MENU_CONTENT: 2,       # the Size stepper; Remove
        CHROME_SURFACE: 12,    # presence toggle, 3 bar-bucket adds, 3 lock keys,
                               # add-at-pointer, dock pin toggle, the lock
                               # layout re-link (spec §4.3 as amended: one entry
                               # that puts a forked screen back whole), and the
                               # widget-choice pair beside it - one pick, and
                               # its own re-link
        BAR_CONTROLLER: 1,     # one snapshot helper serving reorder and remove
        LOCK_REORDER: 3,       # one literal path per island
        DRAG_APPS: 2,          # the dock's reorder commit; the badge unpin
    }
    for path, count in expected.items():
        found = code(path).count("editUndoPush")
        assert found == count, \
            f"{path.name}: {found} undo pushes where the contract expects {count}"
    # The drag-release push is guarded on the commit having MOVED something:
    # commitPosition runs for every release of a draggable widget, click
    # included, and an unguarded push fills the stack with entries that undo
    # to where the widget already is.
    widget = code(PLUGIN_WIDGET)
    assert re.search(
        r"if \(beforeX !== rootWidget\.targetX \|\| beforeY !== rootWidget\.targetY\)",
        widget), "the drag-release push lost its moved-something guard"


if __name__ == "__main__":
    raise SystemExit(run(globals()))
