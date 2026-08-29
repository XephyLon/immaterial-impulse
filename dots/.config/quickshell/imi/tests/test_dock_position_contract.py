#!/usr/bin/env python3
"""The dock's position derives from one place, and nothing names a side twice.

The dock used to spell its geometry out in four files that had to agree:
Dock.qml's anchors and exclusive zone, and hand-written topMargin/bottomMargin
pairs in the dock body, the separator and the app buttons. Four coordinated
edits is how a mirror drifts - one file gets flipped and the others quietly
keep pointing at the bottom of the screen.

The vertical edges made that worse rather than merely wider, which is why the
spec asked for a lint before the second layout existed (§7 step 6, folded in
here): a horizontal dock spelling out `topMargin` is correct and a vertical one
spelling out the same thing is not wrong-looking, it is wrong on the axis the
layout owns - the inset eats into the strip of icons instead of into the dock's
depth, and nothing errors.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCK = ROOT / "modules/imi/dock/Dock.qml"
GEOMETRY = ROOT / "modules/imi/dock/dock_geometry.js"
CONFIG = ROOT / "modules/common/Config.qml"
DEFAULTS = ROOT / "defaults/config.json"
SETTINGS = ROOT / "modules/imi/settings/pages/BarConfig.qml"
RULES = ROOT.parents[2] / ".config/hypr/hyprland/rules.lua"

WIDGETS = ROOT / "modules/common/widgets"
# The dock's own pieces moved out of the shared folder: they drive four
# services and pin apps through Config, which a shared widget may not.
DOCK_DIR = ROOT / "modules/imi/dock"
DRAG_APPS = DOCK_DIR / "DragApps.qml"
APP_BUTTON = DOCK_DIR / "DockAppButton.qml"
BUTTON = WIDGETS / "DockButton.qml"
SEPARATOR = WIDGETS / "DockSeparator.qml"
ICON_MOTION = WIDGETS / "DockIconMotion.qml"
CONTEXT_MENU = DOCK_DIR / "DockContextMenu.qml"
DOCK_TO_PANEL = ROOT / "modules/imi/bar/DocktoPanel.qml"

# Everything that has to know which way the dock is facing. DockAppButton is
# rooted on DockButton and inherits `dockEdge`/`dockVertical` from it, which is
# the only sanctioned way to not read the config yourself.
EDGE_AWARE = [DOCK, BUTTON, SEPARATOR, APP_BUTTON, ICON_MOTION, DRAG_APPS, CONTEXT_MENU]

# A margin, inset or anchor bound to a named side while naming one of the two
# tokens whose asymmetry the edge decides.
SIDE_BOUND_TOKEN = re.compile(
    r"(top|bottom|left|right)(Margin|Inset)\s*:[^\n]*"
    r"(elevationMargin|hyprlandGapsOut)")

# The anchor LINES, which decide an item's geometry. `centerIn`, the margins
# and the two centre offsets are deliberately absent: they are numbers and a
# whole-item shorthand, and neither can put two anchors on one axis.
ANCHOR_LINES = ("top", "bottom", "left", "right",
                "horizontalCenter", "verticalCenter")
AXES = (({"left", "right"}, "horizontalCenter"),
        ({"top", "bottom"}, "verticalCenter"))

# One anchor line and whatever it is bound to.
ANCHOR_LINE_BINDING = re.compile(
    r"(?:^|\n)\s*(?:anchors\.)?(" + "|".join(ANCHOR_LINES) + r")\s*:([^\n]*)")
# ...bound to something that varies with the dock's edge. `Side` catches the
# derived names (outwardSide, dotSide, revealSide, dockSide); `vertical` needs
# its word boundary or it matches `verticalCenter`.
EDGE_DEPENDENT = re.compile(r"\b(vertical|dockVertical|dockEdge|edge)\b|Side\b")
# The layer surface's own anchors are the exception: booleans the compositor
# applies to a surface, not QQuickAnchors, and the one thing that genuinely
# does have to change with the edge.
SURFACE_ANCHORS = "DockGeometry.anchors("


def anchor_groups(source):
    """The anchor-line names each item binds, one set per declaration site."""
    for opening in re.finditer(r"\banchors\s*\{", source):
        index, depth = opening.end(), 1
        while depth and index < len(source):
            depth += {"{": 1, "}": -1}.get(source[index], 0)
            index += 1
        block = source[opening.end():index - 1]
        yield ({name for name in ANCHOR_LINES
                if re.search(rf"(?:^|\n)\s*{name}\s*:", block)}, block)

    # ...and the same declarations written out one `anchors.x:` line at a
    # time, which is one item's anchors exactly when the lines are adjacent.
    names, lines = set(), []
    for line in source.splitlines() + [""]:
        dotted = re.match(r"\s*anchors\.(\w+)\s*:", line)
        if dotted:
            if dotted.group(1) in ANCHOR_LINES:
                names.add(dotted.group(1))
            lines.append(line)
            continue
        if names:
            yield names, "\n".join(lines)
        names, lines = set(), []


class DockPositionContractTest(unittest.TestCase):
    def qml_sources(self):
        for path in sorted(ROOT.glob("modules/**/*.qml")):
            yield path, path.read_text(encoding="utf-8")

    def test_the_dock_reads_its_geometry_rather_than_spelling_it(self):
        source = DOCK.read_text(encoding="utf-8")
        self.assertIn("dock_geometry.js", source)
        for derived in ("DockGeometry.thickness(", "DockGeometry.exclusiveZone(",
                        "DockGeometry.anchors(", "DockGeometry.margins(",
                        "DockGeometry.revealOffsets(", "DockGeometry.hideDirection(",
                        "DockGeometry.contentBox("):
            self.assertIn(derived, source, f"{derived} is spelled out again")
        # The arithmetic itself may not reappear in the QML.
        self.assertNotIn("anchors { bottom: true; left: true; right: true }", source,
                         "the anchors are literal again")

    def test_the_edge_comes_from_config_and_survives_nonsense(self):
        self.assertIn("property string edge:", CONFIG.read_text(encoding="utf-8"))
        self.assertIn('"edge": "bottom"', DEFAULTS.read_text(encoding="utf-8"))
        source = DOCK.read_text(encoding="utf-8")
        self.assertIn("DockGeometry.normalizedEdge(", source,
                      "a hand-edited config or an old preset must not unanchor the dock")

    # ---- one derivation, and only one -----------------------------------

    def test_nothing_derives_the_docks_edge_a_second_way(self):
        # The direct analogue of lint_bar_popup_overlay_static.py's rule for
        # barEdge. A file may read the stored key, but only straight into
        # normalizedEdge() - anything else is a second answer to "which way is
        # the dock facing", and the one that rots is whichever is off screen.
        for path, source in self.qml_sources():
            if "dock.edge" not in source:
                continue
            self.assertIn("dock_geometry.js", source,
                          f"{path.name} reads dock.edge without the one derivation")
            if path == SETTINGS:
                # The settings row shows and writes the stored value because it
                # IS the setting, not a consequence of it. Normalising there
                # would silently rewrite a hand-edited config on page open.
                continue
            for read in re.finditer(r"Config\.options\??\.dock\.edge", source):
                window = source[max(0, read.start() - 120):read.start()]
                self.assertIn("DockGeometry.normalizedEdge(", window,
                              f"{path.name} reads dock.edge outside normalizedEdge()")

    def test_nobody_compares_the_stored_edge_to_a_side(self):
        # The shape this replaced: `(Config.options?.dock.edge ?? "bottom") === "top"`,
        # which is a derivation wearing a comparison's clothes - it answers
        # "top or not top", which is the whole question at two edges and half
        # of it at four.
        for path, source in self.qml_sources():
            self.assertIsNone(
                re.search(r'dock\.edge[^\n]*\?\?[^\n]*"\s*\)?\s*(===|==|!==|!=)', source),
                f"{path.name} compares the stored edge to a side instead of deriving it")

    def test_the_bars_pair_becomes_an_edge_in_exactly_one_place(self):
        # Three files already re-derive a name from bar.bottom + bar.vertical.
        # Anything that has to compare the dock's edge against the bar's goes
        # through the module, or the comparison is between two vocabularies.
        for path, source in self.qml_sources():
            if "dock.edge" not in source:
                continue
            if "bar.vertical" not in source or "bar.bottom" not in source:
                continue
            self.assertIn("DockGeometry.barEdge(", source,
                          f"{path.name} spells the bar's overloaded pair out again")

    def test_the_bar_widget_keeps_following_the_bar(self):
        # DocktoPanel renders the same pinnedApps inside the bar. Its placement
        # follows the BAR and must keep doing so (spec §8).
        source = DOCK_TO_PANEL.read_text(encoding="utf-8")
        self.assertNotIn("dock.edge", source,
                         "the bar's dock strip must not follow the dock's edge")

    def test_no_widget_binds_the_asymmetric_pair_to_a_named_side(self):
        # elevationMargin inward, hyprlandGapsOut outward - which side each
        # lands on is the edge's business, and a widget that decides is correct
        # at one edge out of four.
        for path in EDGE_AWARE:
            source = path.read_text(encoding="utf-8")
            offender = SIDE_BOUND_TOKEN.search(source)
            self.assertIsNone(
                offender,
                f"{path.name} binds the elevation/gap pair to a side: "
                f"{offender.group(0) if offender else ''}")

    def test_the_turn_never_moves_an_anchor_onto_an_occupied_axis(self):
        # The dock's body, its strip and its hover area each anchored the two
        # ends of whichever axis they spanned and centred on the other, so the
        # SET of anchors changed when the dock turned. Qt does not merely
        # ignore an axis holding two anchors during that turn:
        #
        #   left + right + horizontalCenter is refused outright, and the item
        #   keeps the anchors of BOTH orientations - measured at 5120x1440
        #   inside a 75x1440 surface, which is a full-height dark band with
        #   the icons spread over a screen's width, of which a side edge shows
        #   75px;
        #
        #   right + horizontalCenter alone makes the ANCHOR write the item's
        #   width (2 * (right - hcenter)) - measured at 5120 against a content
        #   item that was already 75 wide - and that write outlives the size
        #   binding it clobbered, because the binding has finished changing by
        #   then and never re-evaluates.
        #
        # Both are silent: no error, no binding loop, and QML that reads
        # correctly. So the check is structural - one axis, one anchor - and
        # the turn is expressed as a size (DockGeometry.contentBox) and an
        # offset (DockGeometry.hideDirection) instead.
        for path in EDGE_AWARE:
            for names, block in anchor_groups(path.read_text(encoding="utf-8")):
                for ends, centre in AXES:
                    if centre in names and names & ends:
                        self.fail(
                            f"{path.name} anchors {sorted(names & ends)} and "
                            f"{centre} on one axis:\n{block.strip()}")

    def test_no_anchor_in_the_dock_changes_with_the_edge(self):
        # The general form of the rule above, and the one that catches the
        # second way an anchor ruins a property: an anchor WRITES whatever it
        # pins, so one that appears when the dock turns overwrites the binding
        # that owns that coordinate, and the binding never runs again to take
        # it back. The window-preview card's `x` was left at 0 that way - it
        # had been written by an `anchors.left` that only exists while the dock
        # is on a side edge, and afterwards the card sat at the end of the
        # strip instead of under the icon the pointer was on.
        #
        # So: the turn is a size, an offset or a coordinate, never an anchor.
        # The layer surface's own anchors are exempt - those are booleans the
        # compositor applies, and they are the one thing that has to change.
        for path in EDGE_AWARE:
            source = path.read_text(encoding="utf-8")
            for line, expression in ANCHOR_LINE_BINDING.findall(source):
                if SURFACE_ANCHORS in expression:
                    continue
                self.assertIsNone(
                    EDGE_DEPENDENT.search(expression),
                    f"{path.name} makes the `{line}` anchor follow the edge:"
                    f"{expression}")

    # ---- the vertical layout --------------------------------------------

    def test_the_strip_flows_with_the_edge_rather_than_being_rebuilt(self):
        # One tree with an orientation (§9 Q2): an orientation change reflows
        # the icons rather than destroying and recreating them, so icon state,
        # hover state and DockLaunchTracker's bookkeeping survive it.
        source = DOCK.read_text(encoding="utf-8")
        self.assertIn("DockGeometry.isVertical(", source)
        self.assertIn("flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight",
                      source, "the icon strip does not turn with the dock")
        self.assertNotIn("RowLayout {\n                            id: dockRow", source,
                         "the strip is a RowLayout again and cannot turn")

    def test_the_reorder_compares_the_axis_the_slots_run_along(self):
        # A vertical layout that lays out plausibly can still have the reorder
        # inert: in a column every slot centre has the same x, so an x-only
        # comparison never finds a different nearest slot and nothing swaps.
        source = DRAG_APPS.read_text(encoding="utf-8")
        self.assertIn("function alongAxis(", source)
        self.assertNotIn("dragHandler.centroid.scenePosition.x\n", source,
                         "the drag still reads one hardcoded axis")
        self.assertIn("root.vertical ? slotOffset : 0", source,
                      "the slots are still placed along x only")

    def test_the_running_dots_answer_for_both_places_they_live(self):
        # The pinned apps' dots are in DragApps and the running unpinned ones
        # in DockAppButton. A dock of pinned icons shows nothing of a change
        # made only to the second.
        for path in (DRAG_APPS, APP_BUTTON):
            source = path.read_text(encoding="utf-8")
            self.assertIn("DockGeometry.outwardSide(", source,
                          f"{path.name}'s running dots do not follow the edge")
            self.assertTrue(
                re.search(r"flow: root\.(vertical|dockVertical) \? Flow\.TopToBottom", source),
                f"{path.name}'s running dots cannot stack beside the icon")

    def test_the_hover_lift_is_a_magnitude_and_a_direction(self):
        source = ICON_MOTION.read_text(encoding="utf-8")
        self.assertIn("DockGeometry.inwardVector(", source)
        self.assertIn("root.liftVector.x", source)
        self.assertIn("root.liftVector.y", source)
        self.assertNotIn("to: -Appearance.spacing.space100", source,
                         "the launch bounce is a bare negative y again")

    def test_the_media_tile_is_absent_at_a_vertical_edge(self):
        # A 240x60 card has no 60x240 form; §9 Q1 hides it rather than holding
        # the position work up for a new component.
        source = DOCK.read_text(encoding="utf-8")
        self.assertIn("Config.options.dock.showMedia && !root.vertical", source)
        # ...and the separators that flank it must read the tile rather than
        # the option, or they hide themselves against something absent.
        self.assertNotIn("!(Config.options.dock.showMedia && dockMedia.hasTrack)", source)

    # ---- the settings row ------------------------------------------------

    def test_the_settings_row_writes_the_string_directly(self):
        source = SETTINGS.read_text(encoding="utf-8")
        self.assertIn('Translation.tr("Dock position")', source)
        self.assertIn("Config.options.dock.edge = newValue", source)
        # The whole argument for a new key rather than parity with the bar's
        # overloaded pair is that nothing has to open-code a bitfield.
        row = source[source.index('Translation.tr("Dock position")'):]
        row = row[:row.index("\n                ConfigSwitch")]
        for edge in ('"top"', '"left"', '"bottom"', '"right"'):
            self.assertIn(edge, row)
        self.assertNotIn("& 1", row)
        self.assertNotIn("| 2", row)

    def test_the_settings_row_refuses_the_auto_hiding_bars_edge(self):
        # Settled as §9 Q3: the shell declines the combination rather than
        # arbitrating two 2px reveal slivers over one row of pixels. Only
        # auto-hide collides - a bottom bar plus a pinned dock is a legitimate
        # arrangement the compositor stacks, and refusing that would forbid
        # something that works.
        source = SETTINGS.read_text(encoding="utf-8")
        self.assertIn("Config.options.bar.autoHide.enable", source,
                      "the refusal is not gated on auto-hide")
        self.assertIn("DockGeometry.barEdge(", source)
        row = source[source.index('Translation.tr("Dock position")'):]
        row = row[:row.index("\n                ConfigSwitch")]
        for edge in ("top", "left", "bottom", "right"):
            self.assertIn(f'disabled: dockEdgeRow.blockedEdge === "{edge}"', row,
                          f"the {edge} option can still be chosen under an auto-hiding bar")
        # The control has to honour it, or the row is decoration.
        widget = (WIDGETS / "ConfigSelectionArray.qml").read_text(encoding="utf-8")
        self.assertIn("modelData.disabled", widget,
                      "ConfigSelectionArray ignores a declined option")

    def test_the_slide_follows_the_surface_rather_than_naming_an_edge(self):
        # `slide bottom` pinned the exit animation to one edge, so a top dock
        # slid downward - into the screen - to leave.
        source = RULES.read_text(encoding="utf-8")
        rule = [line for line in source.splitlines()
                if 'namespace = "quickshell:dock"' in line and "animation" in line]
        self.assertEqual(len(rule), 1, "one animation rule for the dock")
        self.assertIn('animation = "slide"', rule[0])
        self.assertNotIn("slide bottom", rule[0])

    def test_the_geometry_module_has_no_side_names_in_its_arithmetic(self):
        # It maps direction onto side names in exactly one function; anywhere
        # else is a second derivation waiting to disagree with the first.
        source = GEOMETRY.read_text(encoding="utf-8")
        body = source[source.index("function thickness"):]
        for function in ("function thickness", "function exclusiveZone", "function insets",
                         "function revealOffsets", "function directedSides",
                         "function axisMargins", "function margins"):
            start = body.index(function)
            end = body.index("\n}", start)
            chunk = body[start:end]
            self.assertFalse(re.search(r'"(top|bottom|left|right)"', chunk),
                             f"{function} names a side")


if __name__ == "__main__":
    unittest.main(verbosity=2)
