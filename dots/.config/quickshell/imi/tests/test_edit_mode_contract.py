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
CHROME_SCOPE = ROOT / "modules/imi/editMode/EditModeChrome.qml"
CHROME_SURFACE = ROOT / "modules/imi/editMode/EditModeChromeSurface.qml"
CHROME_CONTENT = ROOT / "modules/imi/editMode/EditModeChromeContent.qml"
DESKTOP_MENU = ROOT / "modules/imi/desktopMenu/DesktopMenu.qml"
RULES = ROOT.parents[1] / "hypr/hyprland/rules.lua"

# Everything that takes part in the mode. Listed rather than globbed so a new
# participant is a deliberate addition to this list, which is where someone
# reads what the rules are.
PARTICIPANTS = [BACKGROUND, CANVAS, WIDGET, BACKGROUND_WIDGET, PLUGIN_WIDGET,
                CHROME_SCOPE, CHROME_SURFACE, CHROME_CONTENT]


def read(path: Path) -> str:
    assert path.exists(), f"{path} is missing - this check has nothing to say"
    return path.read_text()


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
    assert len(applied) == 3, \
        (f"expected the wallpaper viewport, the widget canvas and the clock depth "
         f"layer to carry the edit transform, found {len(applied)}")
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
    # The four answers the module gives, and no branch invented beside them.
    for answer in ("cancelGesture", "clearSelection"):
        assert answer in body, f"the handler ignores the module's {answer}"


def test_the_global_lock_is_suppressed_and_never_written():
    # A write would destroy a stored preference and leave the desktop unlocked
    # once the mode ended. Only the two places that mean "the user asked for the
    # lock to change" may write it.
    writers = {
        # The desktop menu's submenu switch, and a right-click on a widget:
        # the two gestures that mean "change the lock".
        "modules/common/widgets/WidgetsSubmenu.qml",
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
        if re.search(r"Behavior on editProgress", path.read_text()):
            behaviours.append(str(path.relative_to(ROOT)))
    assert behaviours == ["GlobalStates.qml"], \
        f"the mode's progress is animated in more than one place: {behaviours}"
    assert re.search(r"readonly property real editProgress: GlobalStates\.editProgress",
                     read(BACKGROUND)), \
        "the desktop must read the shared scalar rather than deriving its own"
    assert "GlobalStates.editProgress" in read(CHROME_SURFACE), \
        "...and so must the chrome"


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
    assert items == ["chrome.toolbarItem", "chrome.tabBarItem"], \
        f"the mask is not exactly the two chrome rects: {items}"
    # ...and nothing else on the surface may take a press. A screen-sized
    # MouseArea would be inside the mask's own hole and eat nothing, which is
    # exactly why it would survive review: it does nothing until the mask grows.
    for path in (CHROME_SURFACE, CHROME_CONTENT):
        body = read(path)
        assert "MouseArea" not in body, \
            f"{path.name} adds a pointer area to a surface whose mask is two rects"


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


def test_the_mode_has_one_way_in_and_the_toolbar_owns_the_way_out():
    # Two controls that disagree about what they do is the failure; two that
    # agree is merely redundant. This picks the first: the desktop menu enters,
    # the toolbar's Done leaves, and neither is the other's second opinion.
    menu = read(DESKTOP_MENU)
    writes = re.findall(r"GlobalStates\.editMode = ([^\n]+)", menu)
    assert writes == ["true"], \
        f"the desktop menu is no longer only the way in: {writes}"
    assert re.search(r"visible:\s*!GlobalStates\.editMode", menu), \
        "the Edit layout row must not sit in the menu doing nothing while the mode is on"
    assert re.search(r"GlobalStates\.editMode = false", read(CHROME_SURFACE)), \
        "the toolbar's Done is the mode's exit"
    # Leaving takes the gesture and the selection with it: Done means stop, and
    # a selection halo left on the desktop has no visible way to be cleared.
    assert re.search(r"onEditModeChanged:[^\n]*clearSelection", read(CANVAS)), \
        "leaving the mode leaves a selection behind"


if __name__ == "__main__":
    raise SystemExit(run(globals()))
