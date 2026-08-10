#!/usr/bin/env python3
"""Source contract: desktop widgets go opaque when transparency is off.

The bug: opacity and frost were governed by two different settings and only
frost knew about the toggle. `PluginWidget`'s blur `Repeater` is gated on
`Config.options.appearance.transparency.enable`, but every widget's panel alpha
came straight from `Config.options.plugins.blurOpacity` (or a hardcoded 0.1),
which is not. Turning transparency off therefore removed the blur and kept the
10% panel - every desktop widget became a hole onto the sharp wallpaper while
the dock and the settings window correctly went opaque.

The derivation itself is behavioural and lives in `tst_plugin_state.qml`. What
cannot be unit-tested is that every *call site* goes through it: a single
widget left reading `blurOpacity` directly is invisible to that test and stays
see-through on screen. These are the greppable pins for that, plus the two
settings-side halves the fix would silently do nothing without.

The last class widens the file past the plugin widgets. The same shape - a
surface applying its own alpha on top of an already-gated token - turned up in
two more places while auditing this one, and they belong in the same file
rather than a sibling: what a future agent greps for is "who is gated on
`transparency.enable`", and splitting that answer in two is how a two-sided
contract drifts apart (AGENT.md, on the validator/renderer whitelists).

Each assertion names the edit it exists to redden.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / "modules/common/plugins/PluginState.qml"
HOST = ROOT / "modules/common/plugins/PluginWidget.qml"
OPTIONS = ROOT / "modules/common/plugins/PluginOptions.qml"
VALIDATOR = ROOT / "modules/common/plugins/PluginValidator.js"
PAGE = ROOT / "modules/imi/settings/pages/PluginsPage.qml"
APPEARANCE = ROOT / "modules/common/Appearance.qml"
DROP_SHELF = ROOT / "modules/imi/dropShelf/DropShelfPanel.qml"
BAR_PAGE = ROOT / "modules/imi/settings/pages/BarConfig.qml"
PANELS_PAGE = ROOT / "modules/imi/settings/pages/SidebarsPanelsConfig.qml"
BUNDLED = ROOT / "modules/common/plugins/bundled"
DESIGN_WIDGETS = ROOT / "modules/common/plugins/designsystem/widgets"

DESIGN_SYSTEM_DESKTOP = (
    "DesktopCurrencyWidget.qml",
    "DesktopMediaWidget.qml",
    "DesktopSystemMonitorWidget.qml",
    "DesktopWeatherWidget.qml",
)


def squashed(path: Path) -> str:
    return re.sub(r"\s+", " ", path.read_text(encoding="utf-8"))


class TheDerivationIsCentral(unittest.TestCase):
    def setUp(self):
        self.src = squashed(STATE)

    def test_plugin_state_owns_it(self):
        """It has to sit where both halves are reachable: Config (the toggle
        and the configured alpha) and the per-plugin option store (the
        opt-out). Anywhere else and one of the two has to be plumbed in.
        """
        self.assertIn("function effectiveBackgroundOpacity(", self.src)
        self.assertIn("function resolveBackgroundOpacity(", self.src)

    def test_it_reads_the_toggle_and_the_opt_out(self):
        """Dropping either term is the whole bug: without the toggle nothing
        changes when transparency goes off, and without `keepTranslucent` the
        opt-out row below becomes a switch that does nothing.
        """
        body = self.src[self.src.index("function effectiveBackgroundOpacity("):]
        body = body[:body.index("function presetPersisted")]
        self.assertIn("Config.options.appearance.transparency.enable", body)
        self.assertIn('"keepTranslucent"', body)
        self.assertIn("Config.options.plugins.blurOpacity", body)

    def test_opaque_means_one_not_zero(self):
        """`transparentize(color, 1 - opacity)` is how every consumer applies
        this, so the opaque end is 1. A 0 here would make every widget
        invisible rather than opaque - and it is the plausible typo.
        """
        self.assertIn(
            "return (transparencyEnabled || keepTranslucent) ? baseOpacity : 1;",
            self.src)


class EveryConsumerGoesThroughIt(unittest.TestCase):
    """The assertion that would have caught the original bug, and the one that
    catches the next widget added without the derivation."""

    def test_no_bundled_widget_reads_blur_opacity_directly(self):
        offenders = [
            path.relative_to(ROOT)
            for path in sorted(BUNDLED.glob("*/*.qml"))
            if "Config.options.plugins.blurOpacity" in path.read_text(encoding="utf-8")
        ]
        self.assertEqual(offenders, [],
                         "these widgets bypass the transparency derivation")

    def test_no_design_system_widget_hardcodes_its_alpha(self):
        """These four shipped `property real backgroundOpacity: 0.1`. The
        literal is only reached by a host that does not assign the property,
        but a literal cannot follow a toggle by construction.
        """
        for name in DESIGN_SYSTEM_DESKTOP:
            src = (DESIGN_WIDGETS / name).read_text(encoding="utf-8")
            self.assertNotIn("property real backgroundOpacity: 0.1", src, name)
            self.assertIn(
                'property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("", 0.1)',
                src, name)

    def test_the_design_system_widgets_import_the_singleton(self):
        """A bareword singleton with no import silently throws on every
        binding evaluation - and NaN geometry from that class of mistake pegs
        a core at 100% CPU (AGENT.md, Design language).
        """
        for name in DESIGN_SYSTEM_DESKTOP:
            src = (DESIGN_WIDGETS / name).read_text(encoding="utf-8")
            self.assertIn("import qs.modules.common.plugins", src, name)

    def test_every_bundled_consumer_names_its_own_plugin_id(self):
        """An empty id would compile, read the global value and silently make
        that widget's opt-out unreachable from its own settings panel.
        """
        for path in sorted(BUNDLED.glob("*/Widget.qml")):
            src = path.read_text(encoding="utf-8")
            for call in re.findall(r"effectiveBackgroundOpacity\(([^)]*)\)", src):
                self.assertRegex(call.strip(), r'^"[^"]+"$',
                                 f"{path.parent.name} passes {call!r}")


class TheOptOutIsReachable(unittest.TestCase):
    """A persisted option with no UI silently does nothing (CONTRIBUTING:
    "Settings additions are two-sided")."""

    def test_the_host_binds_it_from_plugin_state(self):
        """Not an assignment: a direct write kills the binding and freezes the
        value for the session while the settings switch appears to work.
        """
        src = squashed(HOST)
        self.assertIn(
            'PluginState.option(manifest.id, "keepTranslucent", '
            'manifest.desktopWidget?.keepTranslucent === true)', src)
        self.assertNotRegex(HOST.read_text(encoding="utf-8"),
                            r"\.keepTranslucent\s*=[^=]")

    def test_the_frost_follows_the_opt_out_too(self):
        """Half a fix is the original bug: a widget exempted from the forced
        opacity but still denied its frost is a translucent panel over a sharp
        wallpaper, which is exactly what was reported.
        """
        src = squashed(HOST)
        self.assertIn(
            "(Config.options.appearance.transparency.enable || rootWidget.keepTranslucent)",
            src)

    def test_the_settings_row_exists(self):
        src = squashed(OPTIONS)
        self.assertIn('key: "keepTranslucent"', src)
        self.assertIn("default: manifest.desktopWidget?.keepTranslucent === true", src)

    def test_the_manifest_field_is_type_checked(self):
        """The other three seeds are validated; an unvalidated fourth would
        accept a string and seed a truthy default nobody can account for.
        """
        self.assertIn(
            'const desktopFlags = ["blur", "locked", "clickThrough", "keepTranslucent"]',
            VALIDATOR.read_text(encoding="utf-8"))


class TheInertControlsSaySo(unittest.TestCase):
    """With transparency off the frost rows govern nothing, unless some widget
    opted out. A live control that does nothing is the next bug report."""

    def setUp(self):
        self.src = squashed(PAGE)

    def test_the_gate_exists_and_accounts_for_the_opt_out(self):
        self.assertIn("readonly property bool widgetTranslucencyApplies:", self.src)
        gate = self.src[self.src.index("readonly property bool widgetTranslucencyApplies:"):]
        gate = gate[:gate.index("// Filter state")]
        self.assertIn("Config.options.appearance.transparency.enable", gate)
        self.assertIn('"keepTranslucent"', gate)

    def test_both_frost_rows_are_gated(self):
        """Gating only the slider leaves its neighbour - the frost selector,
        dead for the same reason - looking live right next to it.
        """
        self.assertEqual(self.src.count("enabled: root.widgetTranslucencyApplies"), 2)


class TheToggleReachesTheOtherPaintedSurfaces(unittest.TestCase):
    """Two non-plugin surfaces had the identical defect: their own alpha,
    applied on top of a token that already drops to opaque, so the toggle
    removed the blur and left the translucency behind.

    Neither routes through `PluginState.effectiveBackgroundOpacity`. That
    function's whole signature is `(pluginId, base, manifestSeed)` and its value
    is resolving a *per-plugin* opt-out; a panel has no plugin id and no
    manifest, so it would pass `""` forever and take a dependency on the plugin
    state store to get back a one-line conditional. The abstraction that
    generalises here is the one `Appearance.qml` already had - a transparency
    amount gated on the switch.
    """

    def test_the_bar_amount_is_gated_beside_the_other_two(self):
        """`bar.backgroundOpacity` used to be inlined raw at colBarBackground.
        Declaring it with backgroundTransparency/contentTransparency is what
        makes "every transparency amount is gated, in one place" greppable.
        """
        src = squashed(APPEARANCE)
        self.assertIn("property real barBackgroundTransparency:", src)
        amount = src[src.index("property real barBackgroundTransparency:"):]
        amount = amount[:amount.index("m3colors:")]
        self.assertIn("Config?.options.appearance.transparency.enable", amount)
        self.assertIn("Config?.options.bar.backgroundOpacity", amount)
        self.assertIn(": 0", amount)

    def test_col_bar_background_reads_the_gated_amount(self):
        """Gating the amount and leaving the token on the raw setting is the
        silent half-fix: the new property would be dead and the bar, vertical
        bar, pills and hug corners would stay see-through exactly as before.
        """
        src = squashed(APPEARANCE)
        self.assertIn(
            "property color colBarBackground: ColorUtils.transparentize(colLayer0, "
            "root.barBackgroundTransparency)", src)
        self.assertNotIn(
            "transparentize(colLayer0, 1 - (Config?.options.bar.backgroundOpacity", src)

    def test_the_drop_shelf_frost_is_gated(self):
        """Frost *is* the translucency in that file - the compositor blurs
        behind the layer, so the only thing "blur" does there is thin the tint.
        Ungated, the shelf shipped 50% see-through onto a sharp wallpaper.
        """
        src = squashed(DROP_SHELF)
        self.assertIn(
            "readonly property bool blurBackground: Config.options.dropShelf.blurBackground "
            "&& Config.options.appearance.transparency.enable", src)

    def test_the_drop_shelf_paint_still_reads_that_property(self):
        """Gating the property matters only if the fill still branches on it -
        an inlined `Config.options.dropShelf.blurBackground` at the Rectangle
        would leave the gate correct and unreachable.
        """
        src = squashed(DROP_SHELF)
        self.assertIn("color: root.blurBackground ? ColorUtils.transparentize("
                      "Appearance.colors.colLayer0, 1 - root.backgroundOpacity) "
                      ": Appearance.colors.colLayer0", src)

    def test_the_now_inert_rows_say_so(self):
        """Same rule as the plugin frost rows: with transparency off none of
        these three move anything, and a live control that does nothing is the
        next bug report.
        """
        bar = squashed(BAR_PAGE)
        self.assertIn("enabled: Config.options.bar.showBackground "
                      "&& Config.options.appearance.transparency.enable", bar)
        panels = squashed(PANELS_PAGE)
        self.assertIn("enabled: Config.options.dropShelf.blurBackground "
                      "&& Config.options.appearance.transparency.enable", panels)
        # The switch's own row, delimited by its icon and its write-back, so the
        # slice cannot drift onto a neighbouring control's `enabled:`.
        start = panels.index('buttonIcon: "blur_on"')
        end = panels.index("Config.options.dropShelf.blurBackground = checked", start)
        self.assertIn("enabled: Config.options.appearance.transparency.enable",
                      panels[start:end])


if __name__ == "__main__":
    unittest.main()
