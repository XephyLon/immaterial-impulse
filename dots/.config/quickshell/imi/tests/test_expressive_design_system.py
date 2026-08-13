#!/usr/bin/env python3
"""Structural guarantees for the shared expressive library and widget plugins."""

import json
import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
DESIGN_SYSTEM = ROOT / "modules/common/plugins/designsystem"
PLUGIN_ROOT = ROOT / "modules/common/plugins/bundled"
PLUGIN_DIRS = (
    "nandoroid-media",
    "nandoroid-system-monitor",
    "nandoroid-weather",
    "nandoroid-currency",
)
EXPECTED_OPTIONS = {
    "nandoroid-media": {"showLyrics", "useRomaji"},
    "nandoroid-system-monitor": {"vertical", "showBattery"},
    # Both widgets declared a `sizeMode` choice option until the host's
    # `__gridSize` took the concept over; their spans are `grid.sizes` now.
    "nandoroid-weather": set(),
    "nandoroid-currency": {"baseCurrency", "quote1", "quote2", "quote3", "quote4"},
}
EXPECTED_ENTRY_TYPES = {
    "nandoroid-media": "Expressive.DesktopMediaWidget",
    "nandoroid-system-monitor": "Expressive.DesktopSystemMonitorWidget",
    "nandoroid-weather": "Expressive.DesktopWeatherWidget",
    "nandoroid-currency": "Expressive.DesktopCurrencyWidget",
}
# Which file in a package instantiates the design-system component. It is the
# package's entry point for all four again: media's per-span layout files -
# which once held everything this module pins about a wrapper - collapsed back
# into Widget.qml when it became the one tree, and the design-system component
# it instantiates (chromeless, for the text and lyrics page) lives there too.
ENTRY_FILES = {}
# ...and the size assertion below moved with it, to the other side: a widget
# whose manifest declares a grid is sized by the host to the span it resolved,
# so its wrapper names spans rather than forwarding a content size.
SIZED_BY_THE_HOST_GRID = {"nandoroid-media", "nandoroid-weather", "nandoroid-currency"}
# Every package whose entry point composes a card, and so must be handed the
# host's drag. `calendar` is not in PLUGIN_DIRS above - it is a first-party
# bundled widget with no upstream to attribute - but its card lifts like the
# rest of them.
TOLD_ABOUT_THE_DRAG = SIZED_BY_THE_HOST_GRID | {"nandoroid-system-monitor", "calendar"}


def entry_file(directory):
    return PLUGIN_ROOT / directory / ENTRY_FILES.get(directory, "Widget.qml")


class ExpressiveDesignSystemTest(unittest.TestCase):
    def test_library_is_not_a_plugin(self):
        self.assertFalse((DESIGN_SYSTEM / "manifest.json").exists())
        self.assertTrue((DESIGN_SYSTEM / "ExpressiveTokens.qml").exists())
        self.assertTrue((DESIGN_SYSTEM / "ComponentRegistry.qml").exists())

    def test_complete_widget_source_is_present(self):
        qml_files = list((DESIGN_SYSTEM / "widgets").rglob("*.qml"))
        self.assertGreaterEqual(len(qml_files), 94)
        weather_icons = list((ROOT / "assets/icons/google-weather").glob("*.svg"))
        self.assertEqual(len(weather_icons), 60)

    def test_every_weather_glyph_names_an_asset_that_exists(self):
        """A `CustomIcon` handed a name with no file draws nothing, silently.

        `weather_glyphs.js` is a lookup table of ~50 asset basenames, half of
        them assembled by concatenating a `_day`/`_night` suffix, and a typo
        in one of them costs exactly one weather condition on one provider -
        which nobody would notice until that condition happened to occur. The
        table is source text, so checking it against the directory is cheap
        and it is the only check that can see the whole of it at once.
        """
        available = {
            path.stem for path in (ROOT / "assets/icons/google-weather").glob("*.svg")
        }
        source = (
            DESIGN_SYSTEM / "widgets" / "weather_glyphs.js"
        ).read_text(encoding="utf-8")

        def table(name, least):
            block = re.search(rf"var {name} = \{{(.*?)\n\}};", source, re.S)
            self.assertIsNotNone(block, f"{name} is still a table literal")
            entries = re.findall(r':\s*"([^"]+)"', block.group(1))
            # Without this the check passes vacuously the moment the table is
            # reformatted out from under the regex, which is the failure mode
            # every source-text check in this suite is warned about.
            self.assertGreaterEqual(len(entries), least, f"{name} was read")
            return entries

        named = set(re.findall(r'return "([^"]+)"', source))
        named |= set(table("_FIXED", 30))
        for stem in table("_DAY_NIGHT", 8):
            named |= {f"{stem}_day", f"{stem}_night"}

        self.assertGreater(len(named), 20, "the fallbacks were read too")
        missing = sorted(named - available)
        self.assertEqual(missing, [], f"no such google-weather asset: {missing}")

    def test_nandoroid_scale_compatibility_is_finite(self):
        appearance = (ROOT / "modules/common/Appearance.qml").read_text(encoding="utf-8")
        self.assertIn("readonly property real effectiveScale: 1.0", appearance)

    def test_user_widgets_are_independent_attributed_plugins(self):
        ids = set()
        for directory in PLUGIN_DIRS:
            package = PLUGIN_ROOT / directory
            manifest = json.loads((package / "manifest.json").read_text(encoding="utf-8"))
            self.assertNotIn(manifest["id"], ids)
            ids.add(manifest["id"])
            self.assertTrue(manifest.get("author"))
            self.assertEqual(manifest.get("license"), "AGPL-3.0")
            self.assertTrue(manifest.get("sourceUrl"))
            self.assertTrue(manifest.get("upstreamRevision"))
            self.assertEqual(manifest["desktopWidget"]["component"], "Widget.qml")
            # Imported widgets own their exact Material geometry. A fixed host
            # canvas produces the oversized rectangular blur seen on desktop.
            self.assertNotIn("defaultWidth", manifest)
            self.assertNotIn("defaultHeight", manifest)
            self.assertTrue((package / "Widget.qml").exists())
            option_keys = {option["key"] for option in manifest.get("options", [])}
            self.assertEqual(option_keys, EXPECTED_OPTIONS[directory])

            wrapper = (package / "Widget.qml").read_text(encoding="utf-8")
            entry = entry_file(directory).read_text(encoding="utf-8")
            self.assertNotIn("target: Config.options", wrapper)
            self.assertNotIn("target: Config.options", entry)
            self.assertIn(EXPECTED_ENTRY_TYPES[directory], entry)
            if directory in SIZED_BY_THE_HOST_GRID:
                self.assertIn("Appearance.sizes.widgetGridSpanX(", wrapper)
                self.assertIn("Appearance.sizes.widgetGridSpanY(", wrapper)
            else:
                self.assertIn("width: implicitWidth", wrapper)
                self.assertIn("height: implicitHeight", wrapper)
            for option_key in option_keys:
                self.assertIn(f'PluginState.option("{manifest["id"]}", "{option_key}"', entry)

    def test_geometry_rects_come_from_the_settled_span_not_the_animating_box(self):
        """`spanW` may not read the box that is currently animating.

        Three trees have now been written with `spanW: root.implicitWidth`,
        and implicitWidth carries a Behavior: every element's rect became a
        per-frame target, so Behaviors never converged and any rect measured
        from the right edge (the media play button, the weather glyph, the
        currency panel and its cells) crawled behind the card instead of
        travelling with it. The settled span's width is a function of the
        span name alone.
        """
        trees = [
            PLUGIN_ROOT / "nandoroid-media/Widget.qml",
            DESIGN_SYSTEM / "widgets/DesktopWeatherWidget.qml",
            DESIGN_SYSTEM / "widgets/DesktopCurrencyWidget.qml",
        ]
        for tree in trees:
            source = tree.read_text(encoding="utf-8")
            self.assertIn("spanW", source, f"{tree.name} declares a span width")
            for line in source.splitlines():
                if "property real spanW" in line or "property real spanH" in line:
                    # `root.width1x1` and friends are settled constants; the
                    # live box is `root.width` / `root.implicitWidth` exactly.
                    for live in (r"\bimplicitWidth\b", r"\bimplicitHeight\b",
                                 r"\broot\.width\b", r"\broot\.height\b"):
                        self.assertIsNone(re.search(live, line),
                                          f"{tree.name}: {line.strip()}")

    def test_every_card_is_told_when_its_widget_is_handled(self):
        """A card that never receives `dragging` silently never lifts.

        The elevation is a property chain - host -> node -> wrapper -> entry
        component -> card - and any link that forgets to forward it produces
        no error, no warning, and a card that simply sits flat while every
        other one rises. The chain is short enough to pin end to end.
        """
        node = (PLUGIN_ROOT.parent / "PluginNode.qml").read_text(encoding="utf-8")
        host = (PLUGIN_ROOT.parent / "PluginWidget.qml").read_text(encoding="utf-8")
        self.assertIn("item.hostDragging = Qt.binding", node)
        self.assertIn("hostDragging: rootWidget.dragging", host)

        for directory in TOLD_ABOUT_THE_DRAG:
            wrapper = (PLUGIN_ROOT / directory / "Widget.qml").read_text(encoding="utf-8")
            self.assertIn("property bool hostDragging", wrapper, directory)
            self.assertIn("dragging: root.hostDragging", wrapper, directory)

        # ...and every card in the components those wrappers instantiate.
        for name in ("DesktopCurrencyWidget", "DesktopWeatherWidget",
                     "DesktopMediaWidget", "DesktopSystemMonitorWidget"):
            source = (DESIGN_SYSTEM / "widgets" / name).with_suffix(".qml") \
                .read_text(encoding="utf-8")
            cards = source.count("WidgetCard {")
            forwarded = source.count("dragging: root.dragging")
            self.assertEqual(cards, forwarded,
                             f"{name}: {cards} cards, {forwarded} told about the drag")

    def test_calendar_draws_its_surface_on_the_shared_card(self):
        """calendar was the copy that had already drifted, and it is back.

        The spec (docs/superpowers/specs/2026-08-11-expressive-morphing-design.md
        §3c) recorded it as a fourth container with a rounding token of its own
        and no tint conditional at all, exempted from the card's lint until it
        could be rebuilt. This is that rebuild pinned: the surface comes from
        WidgetCard, the frost record comes from that same card so the widget
        cannot disagree with it about where the frost goes, and the shadow is
        the card's rather than a StyledRectangularShadow hung behind it.
        """
        package = PLUGIN_ROOT / "calendar"
        widget = (package / "Widget.qml").read_text(encoding="utf-8")
        manifest = json.loads((package / "manifest.json").read_text(encoding="utf-8"))

        self.assertIn('import "../../designsystem/widgets" as Expressive', widget)
        self.assertIn("Expressive.WidgetCard {", widget)
        self.assertEqual(widget.count("Expressive.WidgetCard {"), 1,
                         "calendar composes exactly one card")
        self.assertIn("readonly property var blurRegions: [card.blurRegion]", widget)
        self.assertIn("managesBlurTint: true", widget)

        # The shadow now comes with the card. Keeping the old one as well
        # would draw two, which reads as one slightly wrong one. Matched as a
        # declaration so the comment above it may still name what it replaced.
        self.assertIsNone(re.search(r"StyledRectangularShadow\s*\{", widget),
                          "the card casts the shadow now")
        # ...and so does the rounding, which is the drift the spec named.
        self.assertNotIn("rounding?.verylarge", widget,
                         "the card owns the rounding")

        # The wrapper contract, from the other side. calendar's two handles
        # choose its size, so its manifest deliberately declares no `grid`:
        # a span is a pixel size the host assigns on every load and would
        # overwrite whichever size the handles last chose. A widget sized by
        # the host reads `hostGridSize`; this one must not, and its box comes
        # off the card it composes.
        self.assertNotIn("grid", manifest)
        self.assertNotIn("hostGridSize", widget)
        self.assertIn("implicitWidth: card.implicitWidth", widget)
        self.assertIn("implicitHeight: card.implicitHeight", widget)

    def test_the_card_shadows_its_body_and_drops_it_while_moving(self):
        """The shadow comes off the BODY, and goes away during motion.

        Taken from the card as a whole it would put a shadow under every label
        and glyph inside it. And re-rendering a blurred copy of the body every
        frame of a morph is the expensive path - the same reason the frost is
        dropped for the duration of the motion.
        """
        card = (DESIGN_SYSTEM / "widgets/WidgetCard.qml").read_text(encoding="utf-8")
        self.assertIn("id: bodySurface", card)
        self.assertIn("shadowEnabled: true", card)
        self.assertIn("layer.enabled: root.shadowVisible", card)
        self.assertIn("root.shadowEnabled && !root.motionActive", card)
        # The layer clips at its item's bounds and the bowed canvas draws
        # outside the card, so the frame is inset negatively by the bow.
        body = card[card.index("id: bodySurface"):]
        self.assertIn("anchors.margins: -Tension.BOW_PX * 2", body[:400])
        # The content layer is a different one and must not gain a shadow.
        content = card[card.index("id: contentItem"):]
        self.assertNotIn("shadow", content.lower())

    def test_the_elevation_numbers_are_the_ones_that_were_picked(self):
        """Tuned on the real wallpaper in ShadowTuningPlayground; a later edit
        that drifts them should be a deliberate re-tune, not a stray diff."""
        appearance = (ROOT / "modules/common/Appearance.qml").read_text(encoding="utf-8")
        for token, value in (("blur", "0.51"), ("shadowOpacity", "0.50"),
                             ("offsetY", "4.0"), ("shadowScale", "1.00"),
                             ("hoverLift", "1.94"), ("dragLift", "2.65")):
            self.assertIn(f"property real {token}: {value}", appearance)

    def test_the_trees_share_one_spelling_of_the_span_animations(self):
        """Twenty-three copies of the same NumberAnimation existed before this.

        The media tree wrote the travel out twenty times inline; weather and
        currency each declared a private `component TravelBehavior` saying the
        same thing. Nothing warns when one of them drifts by a curve - it just
        looks slightly wrong next to the others - so the spelling is shared and
        the private ones may not come back.
        """
        trees = {
            "media": PLUGIN_ROOT / "nandoroid-media/Widget.qml",
            "weather": DESIGN_SYSTEM / "widgets/DesktopWeatherWidget.qml",
            "currency": DESIGN_SYSTEM / "widgets/DesktopCurrencyWidget.qml",
        }
        for name, path in trees.items():
            source = path.read_text(encoding="utf-8")
            self.assertNotIn("component TravelBehavior", source, name)
            self.assertNotIn("component FadeBehavior", source, name)
            self.assertNotIn("expressiveDefaultSpatial", source,
                             f"{name} spells the travel curve itself")
            self.assertIn("SpanTravel {}", source, name)
        for component in ("SpanTravel.qml", "SpanFade.qml"):
            self.assertTrue((DESIGN_SYSTEM / "widgets" / component).exists())

    def test_the_morphing_containers_share_their_mechanics(self):
        """Three shape modules, one set of bounds-and-cache maths.

        weather_shapes and currency_shapes were byte-identical apart from
        their shape tables, and media carried a third copy of the bounds loop.
        What legitimately differs per widget is the polygons and their names;
        that is all these files may now hold.
        """
        shared = DESIGN_SYSTEM / "widgets/shapes/shape_morph.js"
        self.assertTrue(shared.exists())
        for path in (DESIGN_SYSTEM / "widgets/weather_shapes.js",
                     DESIGN_SYSTEM / "widgets/currency_shapes.js",
                     PLUGIN_ROOT / "nandoroid-media/media_shapes.js"):
            source = path.read_text(encoding="utf-8")
            self.assertIn("shape_morph.js", source, path.name)
            self.assertNotIn("minX = Infinity", source,
                             f"{path.name} keeps its own copy of the bounds loop")
        for path in (DESIGN_SYSTEM / "widgets/weather_shapes.js",
                     DESIGN_SYSTEM / "widgets/currency_shapes.js"):
            source = path.read_text(encoding="utf-8")
            self.assertNotIn("new MorphLib.Morph", source,
                             f"{path.name} builds Morphs the shared cache owns")

    def test_the_media_tree_answers_the_blur_contract_itself(self):
        """One tree, one card, one region list.

        The wrapper used to forward `blurRegions`/`managesBlurTint` off
        whichever layout file its Loader held, and this test made every layout
        answer. The one tree ended the dispatch: the card is a shared element,
        so the tree declares the contract directly from it, and a span change
        cannot swap in a layout that forgot - there is nothing left to swap.
        """
        package = PLUGIN_ROOT / "nandoroid-media"
        wrapper = (package / "Widget.qml").read_text(encoding="utf-8")
        self.assertIn("blurRegions: [bgCard.blurRegion]", wrapper)
        self.assertIn("managesBlurTint: true", wrapper)
        self.assertNotIn("layout.item", wrapper,
                         "the per-span Loader dispatch must not return")
        for dead in ("LayoutLarge.qml", "LayoutCookie.qml", "LayoutCompact.qml"):
            self.assertFalse((package / dead).exists(),
                             f"{dead} is the destroy the tree replaced")

    def test_system_monitor_third_card_can_show_the_battery(self):
        """The built-in this widget replaced showed Battery on a laptop.

        The port was always Disk, so laptops silently lost the reading in the
        dedup. The decision belongs to the wrapper (the design system's entry
        component keeps its upstream default), and the third card's three
        readings - fill level, percentage, label - must all follow the same
        flag or the card renders a battery icon over a disk number.
        """
        package = PLUGIN_ROOT / "nandoroid-system-monitor"
        monitor = (DESIGN_SYSTEM / "widgets" / "DesktopSystemMonitorWidget.qml").read_text(
            encoding="utf-8"
        )
        wrapper = (package / "Widget.qml").read_text(encoding="utf-8")
        helper = (package / "ThirdCard.js").read_text(encoding="utf-8")

        self.assertIn("property bool showBattery: false", monitor,
                      "the injected flag must default to the upstream rendering")
        self.assertIn("Battery.percentage", monitor)
        for binding in ("root.thirdCardLevel", "root.thirdCardIcon", "root.thirdCardLabel"):
            self.assertIn(binding, monitor,
                          f"the third card must read {binding}, not a disk-only expression")
        level = re.search(
            r"readonly property real thirdCardLevel:.*?(?=\n\s*readonly property string)",
            monitor, re.S)
        self.assertIsNotNone(level, "the third card needs one shared level expression")
        self.assertIn("SystemData.diskStats", level.group(0))
        self.assertEqual(
            monitor.count("SystemData.diskStats"),
            level.group(0).count("SystemData.diskStats"),
            "the disk reading must not survive anywhere but the level expression, "
            "or the battery branch renders a battery icon over a disk number",
        )

        self.assertIn("function showsBattery(", helper)
        self.assertIn("import qs.services", wrapper,
                      "Battery is not transitive through qs.modules.common")
        self.assertIn("Battery.available", wrapper,
                      "availability, not the option alone, gates the battery card")
        self.assertIn("ThirdCard.showsBattery(", wrapper)

    def test_currency_is_startup_safe(self):
        currency = json.loads(
            (PLUGIN_ROOT / "nandoroid-currency" / "manifest.json").read_text(encoding="utf-8")
        )
        self.assertTrue(currency["startupSafe"])
        self.assertNotIn("defaultWidth", currency)
        self.assertNotIn("defaultHeight", currency)
        background = (ROOT / "modules/imi/background/Background.qml").read_text(encoding="utf-8")
        self.assertIn("modelData.startupSafe !== false", background)
        host = (ROOT / "modules/common/plugins/PluginWidget.qml").read_text(encoding="utf-8")
        # The node renders above the frost (z 1). The z moved from the node
        # itself to nodeLayerFrame - the padded wrapper carrying the bounded
        # layer, sized with room for the resize bow - so the contract is that
        # the frame is z 1 and the node lives inside it.
        self.assertRegex(host, r"id:\s*nodeLayerFrame\s*z:\s*1\b")
        frame_index = host.index("id: nodeLayerFrame")
        node_index = host.index("id: pluginNode")
        self.assertLess(frame_index, node_index,
                        "the node must sit inside the layered frame")
        currency_widget = (
            DESIGN_SYSTEM / "widgets" / "DesktopCurrencyWidget.qml"
        ).read_text(encoding="utf-8")
        self.assertNotIn("Config.options.appearance.currencyWidget.baseCurrency =", currency_widget)
        self.assertNotIn("Config.options.appearance.currencyWidget.quote", currency_widget)
        self.assertIn("signal baseCurrencyRequested", currency_widget)
        self.assertIn("signal quoteCurrencyRequested", currency_widget)

    def test_imported_service_compatibility_is_explicit(self):
        date_time = (ROOT / "services" / "DateTime.qml").read_text(encoding="utf-8")
        for field in ("currentTime", "currentDate", "hours", "minutes", "seconds", "time12h"):
            self.assertRegex(date_time, rf"property\s+\w+\s+{field}\s*:")

        weather = (DESIGN_SYSTEM / "widgets" / "DesktopWeatherWidget.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("Weather.current", weather)
        self.assertNotIn("Weather.todayHigh", weather)
        self.assertNotIn("Weather.todayLow", weather)

    def test_weather_and_currency_resize_through_the_host_not_their_own_grip(self):
        """Both widgets used to draw a `swap_horiz` grip in their bottom-right
        corner, writing a plugin-declared `sizeMode` option. The host now draws
        its own grip in that exact corner for any manifest offering several
        spans, so keeping theirs would stack two controls on one spot - and
        theirs gated on a legacy `cfg.locked` rather than the host's resolved
        lock, so it stayed live on a pinned widget.
        """
        for directory, component, default in (
                ("nandoroid-weather", "DesktopWeatherWidget", "3x1"),
                ("nandoroid-currency", "DesktopCurrencyWidget", "2x1")):
            widget = (DESIGN_SYSTEM / "widgets" / f"{component}.qml").read_text(
                encoding="utf-8")
            wrapper = (PLUGIN_ROOT / directory / "Widget.qml").read_text(
                encoding="utf-8")
            manifest = json.loads(
                (PLUGIN_ROOT / directory / "manifest.json").read_text(encoding="utf-8"))

            self.assertNotIn("sizeModeRequested", widget,
                             f"{component} still asks to change its own size")
            self.assertNotIn("id: resizeHandle", widget,
                             f"{component} still draws a second resize grip")
            self.assertNotIn('"sizeMode"', wrapper,
                             f"{directory} still reads the retired option "
                             "out of PluginState")

            # The host owns which size; the widget owns what that size looks
            # like, which is why the span still arrives as a name.
            self.assertIn(f'sizeMode: root.hostGridSize || "{default}"', wrapper)
            self.assertIn("property string hostGridSize", wrapper)

            # ...and the manifest is where the spans on offer are declared now.
            self.assertNotIn(
                "sizeMode",
                json.dumps(manifest.get("options", []) or []),
                f"{directory} still declares a sizeMode option")
            self.assertGreater(len(manifest["grid"]["sizes"]), 1,
                               f"{directory} must offer the spans it has layouts for")

    def test_plugin_blur_supports_tint_and_widget_regions(self):
        options = (ROOT / "modules/common/plugins/PluginOptions.qml").read_text(encoding="utf-8")
        host = (ROOT / "modules/common/plugins/PluginWidget.qml").read_text(encoding="utf-8")
        node = (ROOT / "modules/common/plugins/PluginNode.qml").read_text(encoding="utf-8")
        monitor = (DESIGN_SYSTEM / "widgets" / "DesktopSystemMonitorWidget.qml").read_text(
            encoding="utf-8"
        )
        wrapper = (PLUGIN_ROOT / "nandoroid-system-monitor" / "Widget.qml").read_text(
            encoding="utf-8"
        )

        config = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
        plugins_page = (ROOT / "modules/imi/settings/pages/PluginsPage.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn('key: "blurTintOpacity"', options)
        self.assertIn("property real blurOpacity: 0.1", config)
        self.assertIn('Translation.tr("Blurred widget opacity")', plugins_page)
        self.assertIn("property bool hasCustomBlurRegions", node)
        self.assertIn("property bool managesBlurTint", node)
        self.assertIn("readonly property var blurRegions", monitor)
        self.assertIn("readonly property var blurRegions: content.blurRegions", wrapper)

        # Currency and weather forward the contract from the design-system
        # component they wrap; media's one tree owns a card of its own and
        # declares the contract directly from it (see
        # test_the_media_tree_answers_the_blur_contract_itself).
        for directory in ("nandoroid-currency", "nandoroid-weather"):
            entry_text = entry_file(directory).read_text(encoding="utf-8")
            self.assertIn("readonly property var blurRegions: content.blurRegions", entry_text)
            self.assertIn("readonly property bool managesBlurTint: content.managesBlurTint", entry_text)
            self.assertIn("useBlurBackground: PluginState.option", entry_text)
            self.assertIn("backgroundOpacity: PluginState.effectiveBackgroundOpacity(", entry_text)
        media = entry_file("nandoroid-media").read_text(encoding="utf-8")
        self.assertIn('useBlurBackground: PluginState.option("nandoroid_media", "blurEnabled"', media)
        self.assertIn("backgroundOpacity: PluginState.effectiveBackgroundOpacity(", media)

        currency = (DESIGN_SYSTEM / "widgets" / "DesktopCurrencyWidget.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("anchors.margins: -8 * Appearance.effectiveScale", currency)
        self.assertIn("signal verticalRequested(bool value)", monitor)
        self.assertIn("root.verticalRequested(!root.isVertical)", monitor)
        self.assertNotIn("margins: -8 * Appearance.effectiveScale", monitor)
        self.assertIn(
            'onVerticalRequested: value => PluginState.setOption("nandoroid_system_monitor", "vertical", value)',
            wrapper,
        )


if __name__ == "__main__":
    unittest.main()
