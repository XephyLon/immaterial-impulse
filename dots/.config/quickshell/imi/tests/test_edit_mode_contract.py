#!/usr/bin/env python3
"""What Edit Mode may do to the desktop, and what it may not.

Stage 3 of docs/superpowers/specs/2026-08-16-edit-mode-design.md, so this
covers the viewport and the desktop only; the chrome surface's half of §11.2
lands with the chrome.

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

# Everything that takes part in the mode. Listed rather than globbed so a new
# participant is a deliberate addition to this list, which is where someone
# reads what the rules are.
PARTICIPANTS = [BACKGROUND, CANVAS, WIDGET, BACKGROUND_WIDGET, PLUGIN_WIDGET]


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
                or re.search(r"property bool editMode", line)
                or "root.editMode" in line
                or "rootWidget.editMode" in line
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


if __name__ == "__main__":
    raise SystemExit(run(globals()))
