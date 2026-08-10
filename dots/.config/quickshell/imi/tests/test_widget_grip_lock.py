#!/usr/bin/env python3
"""Source contract for the resize/toggle grips honouring the host's lock.

`background.widgetsLocked` used to be the only lock a grip knew about, so a
widget that was locked *per widget* still drew its grip and could still be
resized - the lock held for dragging and not for the one other gesture that
changes the widget's geometry. The grips now read the host's resolved
`interactionLocked`, forwarded through `PluginNode` the same way `screenName`
and `hostColText` are.

None of this is instantiable by the qmltestrunner suite - it needs Quickshell's
layer-shell types and a real `WidgetCanvas` parent - so these are the greppable
pins that run in CI. `WidgetGripLockRuntimeTest.qml` is the behavioural half:
it builds the three real widgets under `qs -p` and drives their grips with
actual mouse events under each lock in turn.

Each assertion below is mutation-checked; the comment on it names the edit it
exists to redden.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
NODE = ROOT / "modules/common/plugins/PluginNode.qml"
HOST = ROOT / "modules/common/plugins/PluginWidget.qml"
BASE = ROOT / "modules/imi/background/widgets/AbstractBackgroundWidget.qml"
BUNDLED = ROOT / "modules/common/plugins/bundled"

# The widgets that draw a grip of their own. Kept explicit rather than
# discovered, so a fourth one growing a grip has to be added here on purpose
# instead of quietly inheriting whatever these three happen to assert.
GRIP_WIDGETS = ("calendar", "world-clock", "custom-image")


def source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def handle_blocks(text: str):
    """Every `id: *Handle` block in a file, keyed by id.

    A grip is a `Rectangle` whose `id` ends in `Handle`, holding the `MouseArea`
    that does the resizing; the block is every line indented at least as far as
    that `id:`.
    """
    blocks = {}
    for found in re.finditer(r"^(\s*)id: (\w*Handle)$", text, re.M):
        start = found.end()
        indent = len(found.group(1))
        body = []
        for line in text[start:].splitlines()[1:]:
            if line.strip() and len(line) - len(line.lstrip()) < indent:
                break
            body.append(line)
        blocks[found.group(2)] = "\n".join(body)
    return blocks


def uncommented(path: Path) -> str:
    """Source with `//` comments stripped.

    Every one of these files *mentions* `background.widgetsLocked` in the
    comment explaining what the grips stopped reading, so a plain substring
    search for it matches the prose and passes vacuously forever.
    """
    return re.sub(r"//[^\n]*", "", source(path))


class TheHostHandsDownTheResolvedLock(unittest.TestCase):
    def test_the_node_declares_it_and_defaults_it_off(self):
        """A `Widget.qml` is also loadable on its own (`qs -p` probes render
        one directly), so the property has to mean something with no host to
        bind it - and "not locked" is the only default that leaves a
        standalone widget usable. Same shape as `screenName: ""`.
        """
        self.assertIn("property bool hostInteractionLocked: false",
                      source(NODE))

    def test_the_node_forwards_it_as_a_binding(self):
        """A plain assignment would freeze the value at load time: the widget
        would be stuck at whatever the lock was when it was created, and every
        later toggle would leave the grip in the wrong state.
        """
        self.assertIn(
            "item.hostInteractionLocked = Qt.binding(() => rootNode.hostInteractionLocked)",
            source(NODE))

    def test_the_node_only_forwards_when_the_widget_asks(self):
        """Assigning onto a widget that never declared the property is the
        "Cannot assign to non-existent property" failure - silent for the
        eleven bundled widgets that have no grip at all.
        """
        self.assertIn("if (item.hostInteractionLocked !== undefined)",
                      source(NODE))

    def test_the_host_forwards_the_resolved_lock(self):
        """The realistic mutation is `positionLocked` here, which reads fine
        and quietly drops the global switch and click-through back out of the
        grip's gate - re-opening two thirds of the bug this fixes.
        """
        self.assertIn("hostInteractionLocked: rootWidget.interactionLocked",
                      source(HOST))

    def test_the_resolved_lock_is_still_the_or_of_all_three(self):
        """`interactionLocked` is the whole contract this forwards, so dropping
        a term from it silently stops the grips honouring that one too. Matched
        as the whole expression rather than as three separate substrings: every
        term also appears elsewhere in the file, so searching for them
        individually passes on a binding that no longer mentions any of them.
        """
        squashed = re.sub(r"\s+", " ", uncommented(BASE))
        self.assertIn(
            "readonly property bool interactionLocked: clickThrough "
            "|| positionLocked || Config.options.background.widgetsLocked",
            squashed)


class EveryGripGatesOnIt(unittest.TestCase):
    """Each grip is a `Rectangle` whose `id` ends in `Handle`, holding the
    `MouseArea` that does the resizing. Gating on `visible` is what makes the
    grip dead and not merely invisible: Qt does not route mouse events into an
    invisible item, so hiding the rectangle disarms the area inside it."""

    def _handles(self, widget_id):
        return handle_blocks(source(BUNDLED / widget_id / "Widget.qml"))

    def test_every_widget_with_a_grip_declares_the_property(self):
        for widget_id in GRIP_WIDGETS:
            self.assertIn("property bool hostInteractionLocked: false",
                          source(BUNDLED / widget_id / "Widget.qml"), widget_id)

    def test_the_grips_are_where_this_thinks_they_are(self):
        """Guards every other assertion in this class. Rename `resizeHandle`
        or reflow the `id:` line and the block scan finds nothing, at which
        point "no handle violates the rule" is true and worthless.
        """
        found = {widget: sorted(self._handles(widget)) for widget in GRIP_WIDGETS}
        self.assertEqual(found, {
            "calendar": ["resizeHandle", "toggleHandle"],
            "custom-image": ["resizeHandle"],
            "world-clock": ["toggleHandle"],
        })

    def test_every_grip_is_hidden_by_the_host_lock(self):
        for widget_id in GRIP_WIDGETS:
            for name, body in self._handles(widget_id).items():
                self.assertIn("!root.hostInteractionLocked", body,
                              f"{widget_id}/{name} does not honour the host lock")

    def test_no_grip_reads_the_global_toggle_directly(self):
        """The actual bug. Reading `background.widgetsLocked` here looks right
        - it is a real lock, and the grip does disappear when it is on - but
        it skips the per-widget lock entirely, so a widget the user pinned on
        its own stays resizable.
        """
        for manifest in sorted(BUNDLED.glob("*/Widget.qml")):
            self.assertNotIn("Config.options.background.widgetsLocked",
                             uncommented(manifest), manifest.parent.name)

    def test_no_widget_assigns_the_forwarded_property(self):
        """`hostInteractionLocked` is handed down as a `Qt.binding`. Anything
        assigning it kills that binding, and the grip then stays armed (or
        stays dead) for the rest of the session no matter what the user does -
        the same trap `PluginState.option` bindings have (plan gap 12).
        """
        for manifest in sorted(BUNDLED.glob("*/Widget.qml")):
            self.assertNotRegex(uncommented(manifest),
                                r"hostInteractionLocked\s*=[^=]",
                                manifest.parent.name)


class TheHostsOwnResizeGrip(unittest.TestCase):
    """The grid resize grip is drawn by `PluginWidget` itself, so a manifest
    opts into it by declaring `grid.sizes` and writes no QML - which also means
    the sweep over bundled widgets above cannot see it. It is the same gesture
    under the same lock, so it is pinned here rather than somewhere new."""

    def _grip(self):
        return handle_blocks(source(HOST))["resizeHandle"]

    def test_the_grip_is_where_this_thinks_it_is(self):
        """Guards every assertion below: rename it and they all pass on
        nothing."""
        self.assertEqual(sorted(handle_blocks(source(HOST))), ["resizeHandle"])
        self.assertIn("MouseArea", self._grip())

    def test_it_honours_the_hosts_resolved_lock(self):
        """A resize changes the widget's geometry exactly as a drag does, so
        every reason the host is locked has to disarm it too."""
        self.assertIn("!rootWidget.interactionLocked", self._grip())

    def test_it_only_exists_for_a_widget_that_offers_more_than_one_span(self):
        """Otherwise every grid widget grows a grip that can only ever pick the
        span it already has."""
        self.assertIn("rootWidget.gridResizable", self._grip())

    def test_the_gate_is_on_visible_so_the_grip_is_dead_and_not_just_hidden(self):
        self.assertRegex(self._grip(), r"visible:[^\n]*rootWidget\.gridResizable")

    def test_it_claims_the_press_from_drag_to_move(self):
        """`AbstractWidget`'s drag-to-move is this widget's own root MouseArea.
        The nested area takes the press, but without `preventStealing` the root
        takes the grab back on the first move and the corner walks the widget
        instead of resizing it.
        """
        self.assertIn("preventStealing: true", self._grip())

    def test_the_drag_is_measured_in_scene_coordinates(self):
        """The grip is anchored to a widget that resizes underneath it while
        the drag is live, so a delta read from the grip's own frame folds the
        resize back into the gesture (AGENT.md: a drag cannot be tracked
        through the item it moves).
        """
        self.assertIn("resizeArea.mapToItem(null,", self._grip())

    def test_escape_cancels_the_resize(self):
        grip = self._grip()
        self.assertIn("Keys.onEscapePressed", grip)
        self.assertIn("rootWidget.cancelGridResize()", grip)

    def test_a_release_commits_whatever_the_preview_settled_on(self):
        """Which is also what makes a release after Escape commit nothing: the
        cancel cleared the preview, so there is no span left to store. Committing
        `storedGridSize`, or reading the preview back after clearing it, both
        read fine and both throw the drag's result away.
        """
        body = re.search(r"function endGridResize\(\) \{(.*?)\n    \}",
                         uncommented(HOST), re.S).group(1)
        self.assertLess(body.index("previewGridSize = null"),
                        body.index("commitGridSize("), body)
        self.assertIn("commitGridSize(chosen)", body)


if __name__ == "__main__":
    unittest.main()
