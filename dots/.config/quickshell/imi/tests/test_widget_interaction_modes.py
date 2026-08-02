#!/usr/bin/env python3
"""Source contract for per-widget lock and click-through.

`AbstractBackgroundWidget` is the base class of every desktop widget the shell
has, and the composition this file pins lives entirely in QML property
bindings on it - nothing the qmltestrunner suite can instantiate, because the
host needs Quickshell's layer-shell types and a real `WidgetCanvas` parent.
`WidgetInteractionRuntimeTest.qml` builds the real thing under `qs -p` and is
the behavioural half of this; these are the greppable pins that run in CI.

Each assertion below is mutation-checked: the comment on it names the specific
edit it exists to redden.
"""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "modules/imi/background/widgets/AbstractBackgroundWidget.qml"
HOST = ROOT / "modules/common/plugins/PluginWidget.qml"
OPTIONS = ROOT / "modules/common/plugins/PluginOptions.qml"
VALIDATOR = ROOT / "modules/common/plugins/PluginValidator.js"
BUNDLED = ROOT / "modules/common/plugins/bundled"
VISUALIZER = BUNDLED / "visualizer/manifest.json"


def squashed(path: Path) -> str:
    """Source with runs of whitespace collapsed, so a reflowed multi-line
    expression still matches. Several of these bindings are long enough that
    the formatter's line breaks are not stable."""
    return re.sub(r"\s+", " ", path.read_text(encoding="utf-8"))


def binding(path: Path, name: str) -> str:
    """Just the right-hand side of the `<name>:` binding, wrapped lines joined.

    Slicing to the next `}` instead swallows the following bindings, which
    made an assertion about this expression's operators pick up the `&&` in a
    neighbouring one and fail for the wrong reason. A wrapped continuation is
    always indented deeper than the line that opened it, so that is the
    boundary used here.
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    pattern = re.compile(
        rf"^(\s*)(?:readonly\s+)?(?:property\s+\w+\s+)?{re.escape(name)}:\s*(.*)$")
    for index, line in enumerate(lines):
        found = pattern.match(line)
        if not found:
            continue
        indent = len(found.group(1))
        parts = [found.group(2)]
        for following in lines[index + 1:]:
            if not following.strip():
                break
            if len(following) - len(following.lstrip()) <= indent:
                break
            parts.append(following.strip())
        return " ".join(parts)
    raise AssertionError(f"{path.name} has no `{name}:` binding")


class TheHostOwnsTheMechanism(unittest.TestCase):
    """The two flags belong to the shared base class, not to a plugin.

    `AbstractBackgroundWidget` is what computes `draggable`, so a per-widget
    lock implemented anywhere else would have to fight that binding.
    """

    def setUp(self):
        self.src = squashed(BASE)

    def test_both_flags_are_declared_and_default_off(self):
        """Neutral defaults are the whole blast-radius argument: this base
        class is under every desktop widget in the shell, so a flag defaulting
        to true would pin or deaden all of them at once.
        """
        self.assertIn("property bool positionLocked: false", self.src)
        self.assertIn("property bool clickThrough: false", self.src)

    def test_the_global_toggle_still_participates(self):
        """Replacing the global lock with the per-widget one - rather than
        combining them - would make "Lock widget positions" a dead switch
        while every other test here still passed.
        """
        self.assertIn("Config.options.background.widgetsLocked",
                      binding(BASE, "interactionLocked"))

    def test_the_three_locks_are_or_ed_not_and_ed(self):
        """`||` -> `&&` is the realistic mutation and it inverts the whole
        design: the global switch would then be required for a per-widget lock
        to do anything, and unlocking globally would unpin a widget the user
        deliberately pinned.
        """
        expr = binding(BASE, "interactionLocked")
        self.assertNotIn("&&", expr, "the locks must OR, never AND")
        self.assertEqual(expr.count("||"), 2, "all three locks must be joined")
        for term in ("clickThrough", "positionLocked",
                     "Config.options.background.widgetsLocked"):
            self.assertIn(term, expr)

    def test_draggable_reads_the_combined_lock(self):
        """Leaving `draggable` on the raw global toggle is the silent failure
        mode - the widget still renders, the settings switch still flips, and
        the widget stays draggable anyway.
        """
        self.assertIn("draggable: placementStrategy === \"free\" && !interactionLocked",
                      self.src)

    def test_click_through_disables_the_widget_subtree(self):
        """`enabled` is the mechanism, not decoration. Qt skips disabled items
        when routing mouse events and `enabled` cascades to children, which is
        what lets the click reach the desktop's right-click area behind the
        widget on the same surface.
        """
        self.assertIn("enabled: !clickThrough", self.src)

    def test_click_through_implies_locked(self):
        """Dragging is pointer input. A click-through widget that still
        reported itself draggable would keep the grab cursor and the hover
        scale-up for a widget the pointer can never actually reach.
        """
        self.assertIn("clickThrough", binding(BASE, "interactionLocked"))

    def test_the_surface_is_not_masked_instead(self):
        """Every desktop widget shares one layer-shell surface, so a Wayland
        input region here would blind all of them together. If a `mask:` ever
        appears in this file, the per-widget story is broken.
        """
        self.assertNotRegex(self.src, r"\bmask:",
                            "click-through must not become a surface input region")


class ThePluginHostBindsThem(unittest.TestCase):
    def setUp(self):
        self.src = squashed(HOST)

    def test_each_flag_is_read_from_plugin_state(self):
        """Plugin ids are dynamic, so this cannot live in Config's fixed
        JsonAdapter schema - that shape has caused native crashes before.
        """
        for prop, key in (("positionLocked", "positionLocked"),
                          ("clickThrough", "clickThrough")):
            expr = binding(HOST, prop)
            self.assertIn(f'PluginState.option(manifest.id, "{key}"', expr,
                          f"{prop} must come from PluginState")

    def test_each_flag_is_seeded_by_the_manifest(self):
        """Without the seed a widget could not ship an opinion at all, and the
        visualizer's `clickThrough: true` would be inert JSON.
        """
        self.assertIn("manifest.desktopWidget?.locked === true",
                      binding(HOST, "positionLocked"))
        self.assertIn("manifest.desktopWidget?.clickThrough === true",
                      binding(HOST, "clickThrough"))

    def test_nothing_assigns_the_flags_directly(self):
        """A `PluginState.option(...)` binding dies on the first direct
        assignment - the property then freezes for the rest of the session
        while the settings toggle appears to do nothing. Every writer has to
        go through `PluginState.setOption`.
        """
        for source in (HOST, BASE, OPTIONS):
            text = source.read_text(encoding="utf-8")
            self.assertNotRegex(
                text, r"\.(positionLocked|clickThrough)\s*=[^=]",
                f"{source.name} assigns an interaction flag directly")


class TheSettingsSideExists(unittest.TestCase):
    """A persisted option with no UI silently does nothing (CONTRIBUTING:
    "Settings additions are two-sided"). These rows are the only way to undo a
    manifest default."""

    def setUp(self):
        self.src = squashed(OPTIONS)

    def _rows(self):
        """The `optionRows` list literal alone.

        Reading to end-of-file instead would swallow the Repeater's own
        `PluginState.option(...)` calls, and every assertion about which rows
        are synthesized here would pass on the generic delegate code.
        """
        start = self.src.index("readonly property var optionRows")
        return self.src[start:self.src.index(".concat(manifest.options", start)]

    def test_both_rows_are_offered(self):
        for key in ("positionLocked", "clickThrough"):
            self.assertIn(f'key: "{key}"', self.src,
                          f"no settings row writes {key}")

    def test_the_rows_default_to_the_manifest_seed(self):
        """A row hardcoding `default: false` would show the visualizer's
        click-through switch as off while the widget behaved as on.
        """
        self.assertIn("default: manifest.desktopWidget?.locked === true", self.src)
        self.assertIn("default: manifest.desktopWidget?.clickThrough === true", self.src)

    def test_the_rows_are_booleans(self):
        """`boolean` is already in PluginValidator's type whitelist and
        PluginOptions' switch. An unlisted type renders no row at all.
        """
        rows = self.src[self.src.index("readonly property var optionRows"):]
        rows = rows[:rows.index("Not a pluginOption on purpose")]
        self.assertEqual(rows.count('type: "boolean"'), 3,
                         "blur, lock and click-through are all boolean rows")

    def test_the_rows_are_desktop_widget_only(self):
        """A bar-only plugin has no draggable surface, so these are as dead
        there as the blur toggle was - they ride the same gate.
        """
        rows = self._rows()
        self.assertIn("hasBlurSurface ?", rows)
        self.assertIn("positionLocked", rows)
        self.assertIn("clickThrough", rows)


class TheManifestFieldsAreValidated(unittest.TestCase):
    def test_the_flags_are_type_checked(self):
        """PluginValidator rejects the whole manifest on a bad field, and the
        only symptom is one `[PluginManager] Error parsing plugin manifest`
        line - so the check has to name the field it rejected.
        """
        src = VALIDATOR.read_text(encoding="utf-8")
        self.assertIn('const desktopFlags = ["blur", "locked", "clickThrough"]', src)
        self.assertIn('" must be a boolean"', src)


class TheVisualizerShipsClickThrough(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads(VISUALIZER.read_text(encoding="utf-8"))

    def test_click_through_is_on_by_default(self):
        self.assertIs(self.manifest["desktopWidget"]["clickThrough"], True)

    def test_it_does_not_also_declare_locked(self):
        """Click-through already implies the lock. Declaring both would leave
        a user who turns click-through off with a widget that is still pinned
        for no visible reason, and no obvious way to work out why.
        """
        self.assertNotIn("locked", self.manifest["desktopWidget"])

    def test_it_is_still_full_bleed(self):
        """The reason it needs click-through at all: no `grid`, so the host
        sizes it from its own implicit width, which the widget binds to the
        whole monitor. Give it a grid and it stops covering the desktop.
        """
        self.assertNotIn("grid", self.manifest)

    def test_no_other_bundled_widget_opts_in(self):
        """The change has to be inert for the twelve widgets nobody asked
        about. This is what proves the default is genuinely off rather than
        off-by-accident in a base class that is under all of them.
        """
        for manifest_path in sorted(BUNDLED.glob("*/manifest.json")):
            if manifest_path == VISUALIZER:
                continue
            entry = json.loads(manifest_path.read_text(encoding="utf-8"))
            desktop = entry.get("desktopWidget") or {}
            self.assertNotIn("clickThrough", desktop, manifest_path.parent.name)
            self.assertNotIn("locked", desktop, manifest_path.parent.name)


if __name__ == "__main__":
    unittest.main()
