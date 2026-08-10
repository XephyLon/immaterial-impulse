#!/usr/bin/env python3
"""Source contract for marquee multi-select and group drag on the widget canvas.

The composition this pins lives in QML property bindings across `WidgetCanvas`,
`AbstractWidget`, `AbstractBackgroundWidget` and `PluginWidget` - none of it
instantiable by the qmltestrunner suite, because the host needs Quickshell's
types and a real canvas parent. `WidgetGroupDragRuntimeTest.qml` builds the
real thing under `qs -p` and is the behavioural half; these are the greppable
pins that run in CI.

Each assertion below is mutation-checked: the comment on it names the specific
edit it exists to redden.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CANVAS = ROOT / "modules/common/widgets/widgetCanvas/WidgetCanvas.qml"
WIDGET = ROOT / "modules/common/widgets/widgetCanvas/AbstractWidget.qml"
BASE = ROOT / "modules/imi/background/widgets/AbstractBackgroundWidget.qml"
HOST = ROOT / "modules/common/plugins/PluginWidget.qml"
BACKGROUND = ROOT / "modules/imi/background/Background.qml"
OVERLAY = ROOT / "modules/imi/overlay/OverlayContent.qml"


def source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def uncommented(path: Path) -> str:
    """Source with `//` comments stripped, so an assertion about what the code
    does cannot be satisfied by the prose explaining what it used to do."""
    return re.sub(r"//[^\n]*", "", source(path))


def squashed(path: Path) -> str:
    return re.sub(r"\s+", " ", uncommented(path))


class TheCanvasOwnsSelection(unittest.TestCase):
    """Selection is canvas state, not widget state (the proposal's first
    decision): widgets read "am I selected" from the canvas, so a selection
    cannot outlive the canvas or leak across monitors."""

    def test_the_marquee_is_opt_in_and_defaults_off(self):
        """The overlay reuses WidgetCanvas (`OverlayContent.qml`) and closes
        itself on a plain click. A marquee defaulting on would turn every
        overlay dismiss-click into a selection gesture instead.
        """
        self.assertIn("property bool selectionEnabled: false",
                      uncommented(CANVAS))

    def test_the_background_opts_its_canvas_in(self):
        """Without this the whole feature is dead code: the desktop is the one
        canvas the marquee was built for.
        """
        self.assertIn("selectionEnabled: true", uncommented(BACKGROUND))

    def test_the_overlay_does_not(self):
        self.assertNotIn("selectionEnabled", uncommented(OVERLAY))

    def test_selection_is_session_state(self):
        """The proposal's open question, answered: selection does not survive
        a reload. The canvas therefore has no business importing either
        persistence backend - a `PluginState` or `Persistent` reference
        appearing here means someone started persisting it.
        """
        text = uncommented(CANVAS)
        self.assertNotIn("PluginState", text)
        self.assertNotIn("Persistent.", text)

    def test_only_draggable_widgets_are_selectable(self):
        """`draggable` already folds in everything that must exclude a widget
        from a group move: the per-widget lock, click-through (the full-bleed
        visualizer ships it, which answers the proposal's "does the visualizer
        select itself on every marquee" question), the global lock, and a
        non-free placement strategy. Filtering on anything narrower re-opens
        one of those holes.
        """
        match = re.search(r"function selectWidgetsInRect[^{]*\{(.*?)\n    \}",
                          uncommented(CANVAS), re.S)
        self.assertIsNotNone(match, "WidgetCanvas has no selectWidgetsInRect")
        self.assertIn(".draggable", match.group(1))

    def test_the_global_lock_clears_the_selection(self):
        """Locking the desktop with two widgets still haloed would leave a
        selection that looks live and does nothing - and would spring back to
        life the moment the lock lifts, moving widgets the user thought were
        long deselected.
        """
        text = squashed(CANVAS)
        self.assertIn("Config.options.background.widgetsLocked", text)
        self.assertIn("clearSelection()", text)


class GroupDragIsRigid(unittest.TestCase):
    """Dragging any selected widget moves the whole selection by one delta.
    The cluster must never deform: the group stops when the first member hits
    an edge."""

    def test_the_clamp_bounds_live_on_the_widget_and_default_open(self):
        """The leader's drag Binding is what moves it, so the group clamp has
        to reach into that Binding - a clamp applied anywhere else lets the
        leader walk on while the followers stop, which is exactly the
        deformation this exists to prevent. Defaulting to +/-Infinity keeps a
        single-widget drag byte-for-byte what it was before this feature.
        """
        text = uncommented(WIDGET)
        for name, value in (("groupDragMinX", "-Infinity"),
                            ("groupDragMaxX", "Infinity"),
                            ("groupDragMinY", "-Infinity"),
                            ("groupDragMaxY", "Infinity")):
            self.assertIn(f"property real {name}: {value}", text)

    def test_the_drag_binding_snaps_first_and_clamps_second(self):
        """Clamp-then-snap can round the leader back off the group bound by up
        to half a grid cell, deforming the cluster at the edge by exactly the
        amount the lattice was supposed to guarantee.
        """
        text = squashed(WIDGET)
        for axis in ("X", "Y"):
            proxy = f"dragProxy.{axis.lower()}"
            self.assertRegex(
                text,
                rf"Math\.max\(root\.groupDragMin{axis}, Math\.min\("
                rf"root\.groupDragMax{axis}, root\.snapEnabled \? "
                rf"root\.snap\({re.escape(proxy)}\) : {re.escape(proxy)}\)\)",
                f"the {axis} drag binding must clamp the snapped value")

    def test_the_widget_reports_its_drag_to_the_canvas(self):
        """The canvas cannot see `drag.active` on its own. Without both calls
        the group never starts (or never commits) and every widget quietly
        goes back to moving alone - all the single-drag tests still green.
        """
        text = uncommented(WIDGET)
        self.assertIn("canvas.widgetDragStarted(root)", text)
        self.assertIn("canvas.widgetDragEnded(root)", text)

    def test_followers_move_with_animation_off(self):
        """A follower is not `dragging`, so its position Behavior is live and
        every incremental group step animates - the cluster swims behind the
        pointer. `groupDragging` is the second gate on the same Behaviors.
        """
        text = squashed(WIDGET)
        self.assertIn("property bool groupDragging: false", text)
        self.assertEqual(
            text.count("enabled: !root.dragging && !root.groupDragging"), 2,
            "both position Behaviors must gate on groupDragging too")

    def test_followers_commit_like_a_released_drag(self):
        """A follower never gets a release event, so the canvas must call the
        same commit path a real release runs - otherwise the follower is left
        with a dead x/y binding (the PR's "naive set-x" trap) and its new
        position evaporates on the next state reload.
        """
        self.assertIn("commitPosition()", uncommented(CANVAS))

    def test_the_release_path_and_the_commit_path_are_one_function(self):
        """Two copies of the write-back is how they drift: a fix to the
        released-drag path (say, a new clamp) that never reaches the group
        path, or the reverse. The base class releases through commitPosition
        and PluginWidget overrides that one function.
        """
        self.assertIn("onReleased: root.commitPosition()", uncommented(BASE))
        self.assertIn("function commitPosition()", uncommented(BASE))
        host = uncommented(HOST)
        self.assertIn("function commitPosition()", host)
        # Anchored to the host's own scope. A nested MouseArea - the grid
        # resize grip - releases a gesture of its own that never touches the
        # widget's position; what must not come back is a handler on the host
        # itself, shadowing the base class's.
        self.assertNotRegex(host, r"(?m)^    onReleased:",
                            "PluginWidget must not keep a second release path")

    def test_the_plugin_commit_still_restores_the_binding_and_persists(self):
        """Dropping `restoreXYBinding()` leaves every group member frozen at
        its last dragged position for the session (forceCenter dies with it);
        dropping `setPosition` makes a group move revert on restart. Both
        halves read fine on their own.
        """
        match = re.search(r"function commitPosition\(\)\s*\{(.*?)\n    \}",
                          uncommented(HOST), re.S)
        self.assertIsNotNone(match)
        body = match.group(1)
        self.assertIn("restoreXYBinding()", body)
        self.assertIn("PluginState.setPosition", body)


class TheSelectionIsVisible(unittest.TestCase):
    def test_widgets_carry_a_selected_flag_and_a_halo_gated_on_it(self):
        """Selected-but-not-dragging needs feedback distinct from the press
        scale (the proposal's fifth point). The halo lives on the widget so it
        tracks a group move with no coordinate mapping; gating it on anything
        but `selected` (say `dragging`) makes selection invisible exactly when
        the user is deciding what to drag.
        """
        text = uncommented(WIDGET)
        self.assertIn("property bool selected:", text)
        self.assertIn("visible: root.selected", text)


if __name__ == "__main__":
    unittest.main()
