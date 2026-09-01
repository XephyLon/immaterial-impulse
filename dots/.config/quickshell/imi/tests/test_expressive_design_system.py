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
    "nandoroid-system-monitor-gpu",
    "nandoroid-weather",
    "nandoroid-currency",
)
EXPECTED_OPTIONS = {
    "nandoroid-media": {"showLyrics"},
    "nandoroid-system-monitor": {"vertical", "showBattery"},
    "nandoroid-system-monitor-gpu": {"vertical"},
    # Both widgets declared a `sizeMode` choice option until the host's
    # `__gridSize` took the concept over; their spans are `grid.sizes` now.
    "nandoroid-weather": set(),
    "nandoroid-currency": {"baseCurrency", "quote1", "quote2", "quote3", "quote4"},
}
EXPECTED_ENTRY_TYPES = {
    "nandoroid-media": "Expressive.DesktopMediaWidget",
    "nandoroid-system-monitor": "Expressive.DesktopSystemMonitorWidget",
    "nandoroid-system-monitor-gpu": "Expressive.DesktopSystemMonitorWidget",
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
TOLD_ABOUT_THE_DRAG = SIZED_BY_THE_HOST_GRID | {
    "nandoroid-system-monitor", "nandoroid-system-monitor-gpu", "calendar"}


def entry_file(directory):
    return PLUGIN_ROOT / directory / ENTRY_FILES.get(directory, "Widget.qml")


# A `spanW`/`spanH` property declaration, however it is qualified.
SPAN_DECLARATION = re.compile(
    r"^[ \t]*(?:readonly\s+)?property\s+\w+\s+(spanW|spanH)\s*:", re.M)


def span_declarations(source):
    """Yield (name, the WHOLE declaration) for each spanW/spanH property.

    The whole one, because two of the three trees write the span as a block
    (`readonly property real spanW: { if (sizeMode === "1x1") ... }`) and a
    check that reads only the line carrying the declaration sees nothing but
    an opening brace. It would pass on `return root.implicitWidth;` sitting
    one line below - which is the same vacuous-by-formatting failure
    CONTRIBUTING.md warns every source-text check about.
    """
    for match in SPAN_DECLARATION.finditer(source):
        yield match.group(1), whole_binding(source, match.end())


def whole_binding(source, start):
    """The whole right-hand side of a binding starting at `start`.

    Brace-balanced when the value is a block, the rest of the line otherwise.
    Extracted from `span_declarations` because the same question - is the value
    a line or a block? - decides whether every other source-text check over a
    QML binding in this file is real or vacuous.
    """
    rest = source[start:]
    body = rest.lstrip(" \t")
    if not body.startswith("{"):
        return rest.split("\n", 1)[0]
    opening = len(rest) - len(body)
    depth = 0
    for index in range(opening, len(rest)):
        depth += {"{": 1, "}": -1}.get(rest[index], 0)
        if depth == 0:
            return rest[:index + 1]
    return rest


# A widget that owns its own size names it here; the host's own spans arrive as
# `hostGridSize` instead.
OWN_SIZE_MODE = re.compile(r"^[ \t]*property\s+string\s+sizeMode\s*:", re.M)
# The two ways a span used to decide what EXISTS rather than where it sits.
SPAN_DISPATCH = re.compile(r"^[ \t]*(sourceComponent|visible)\s*:", re.M)


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

        Swept rather than enumerated, and read whole rather than by line.
        The first version named the three trees that existed and looked only
        at the line carrying the declaration - so a fourth tree was invisible
        to it, and weather, whose span is a block, was checked against the
        text `readonly property real spanW: {` and nothing else. Both halves
        are the failure this file already records one method down: a check
        that enumerates its subjects only ever guards the subjects someone
        remembered, and one with a baked-in shape passes vacuously the moment
        the shape changes.
        """
        known = {
            (PLUGIN_ROOT / "nandoroid-media/Widget.qml").resolve(),
            (DESIGN_SYSTEM / "widgets/DesktopWeatherWidget.qml").resolve(),
            (DESIGN_SYSTEM / "widgets/DesktopCurrencyWidget.qml").resolve(),
        }
        swept = set()
        for path in sorted(ROOT.rglob("*.qml")):
            if "tests" in path.relative_to(ROOT).parts:
                continue
            for name, declaration in span_declarations(
                    path.read_text(encoding="utf-8")):
                swept.add(path.resolve())
                # `root.width1x1` and friends are settled constants; the
                # live box is `root.width` / `root.implicitWidth` exactly.
                for live in (r"\bimplicitWidth\b", r"\bimplicitHeight\b",
                             r"\broot\.width\b", r"\broot\.height\b"):
                    self.assertIsNone(
                        re.search(live, declaration),
                        f"{path.name}: {name} reads the animating box:\n"
                        f"{declaration.strip()}")
        self.assertEqual(sorted(path.name for path in known - swept), [],
                         "the sweep stopped seeing a tree that declares a span")

    def test_a_widget_that_owns_its_span_morphs_in_one_tree(self):
        """A span may decide where an element sits, never whether it exists.

        docs/widget-standards-audit-2026-08-16.md's gap #1: calendar dispatched
        three whole `Component`s through one `Loader` keyed on `sizeMode`, and
        world-clock switched three subtrees with `visible`. Both destroy the
        content and rebuild it in a single frame in the middle of a resize,
        which is the interaction those widgets are used through - and both were
        invisible to every check here, because
        `test_the_media_tree_answers_the_blur_contract_itself` names the media
        package and nothing else.

        So this sweeps instead of naming: any widget declaring its own
        `sizeMode` must not let that name reach a `sourceComponent` or a
        `visible`. Read whole rather than by line, because calendar's Loader
        wrote its dispatch as a block and a line-scoped check would have seen
        `sourceComponent: {` and passed.

        `opacity` is deliberately not on the list. An element with no home at a
        span fades where it stands, which is the mechanism this asks for; what
        it forbids is the element ceasing to exist.
        """
        swept = {}
        for path in sorted(PLUGIN_ROOT.rglob("Widget.qml")):
            source = path.read_text(encoding="utf-8")
            if not OWN_SIZE_MODE.search(source):
                continue
            package = path.parent.name
            swept[package] = path
            for match in SPAN_DISPATCH.finditer(source):
                binding = whole_binding(source, match.end())
                self.assertNotIn(
                    "sizeMode", binding,
                    f"{package}/{path.name}: `{match.group(1)}` is decided by "
                    f"the span, so the span destroys and rebuilds the content:"
                    f"\n{binding.strip()}")

        # calendar and world-clock owned their spans until both adopted
        # `grid.sizes`; the sweep stays armed for the next widget that
        # declares a sizeMode of its own.
        self.assertEqual(sorted(swept), [],
                         "a widget owns its span again - its dispatches are "
                         "held to the one-tree rule above")

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
            # ...and that `root` is THIS file. Without the id, `root.hostDragging`
            # resolves by dynamic scope up the creation chain, reads undefined,
            # and the card silently never lifts - which is how the system
            # monitor shipped with a dead drag while this very loop passed on
            # the text being spelled correctly.
            self.assertRegex(wrapper, r"(?m)^\s*id: root\s*$",
                             f"{directory}: `root.` names nothing in this file")

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

        # The wrapper contract, from the other side. calendar's size is the
        # HOST's now: the manifest offers four spans, the widget reads the
        # resolved one back as `hostGridSize`, and its own two corner handles
        # went with the option they wrote (the grip, the Size row and the
        # edit stepper are the three faces of `__gridSize`).
        self.assertIn("grid", manifest)
        self.assertEqual(
            [(size["cols"], size["rows"]) for size in manifest["grid"]["sizes"]],
            [(1, 1), (2, 1), (2, 2), (3, 2)])
        self.assertIn("hostGridSize", widget)
        self.assertIn("handlesSpanTransition: true", widget,
                      "every element travels or fades on its own Behaviors; "
                      "the host's midpoint dissolve would sit on top of that")
        # The implicit size is the settled span - the probe fallback; the
        # host sizes the node to its own animating box.
        self.assertIn("implicitWidth: root.spanW", widget)
        self.assertIn("implicitHeight: root.spanH", widget)

    def test_the_five_folded_widgets_are_told_when_they_are_handled(self):
        """The same chain, for the widgets that were never cards.

        Four of them are the loaded item themselves, so the host reaches them
        directly; the two clock styles are one Loader further down, which is
        the extra link the clock package's wrapper has to carry. A link that
        forgets produces no error - just a widget that alone never lifts.
        """
        for directory in ("world-clock", "user-card", "custom-image", "clock"):
            wrapper = (PLUGIN_ROOT / directory / "Widget.qml").read_text(encoding="utf-8")
            self.assertIn("property bool hostDragging", wrapper, directory)

        world_clock = (PLUGIN_ROOT / "world-clock/Widget.qml").read_text(encoding="utf-8")
        self.assertIn("Expressive.WidgetCard {", world_clock,
                      "the one card-shaped widget of the five takes the component")
        self.assertIn("dragging: root.hostDragging", world_clock)

        # The other four are not cards - a cookie, a punched glyph grid, a
        # shape-masked image and a card with an avatar off its edge - so they
        # take the tokens through WidgetElevation instead.
        for path in ("user-card/Widget.qml", "custom-image/Widget.qml",
                     "clock/CookieClock.qml", "clock/PixelClock.qml"):
            source = (PLUGIN_ROOT / path).read_text(encoding="utf-8")
            self.assertIn("Expressive.WidgetElevation {", source, path)

        clock = (PLUGIN_ROOT / "clock/Widget.qml").read_text(encoding="utf-8")
        self.assertEqual(clock.count("dragging: root.hostDragging"), 2,
                         "both clock styles that draw a body take the drag")
        for style in ("clock/CookieClock.qml", "clock/PixelClock.qml"):
            source = (PLUGIN_ROOT / style).read_text(encoding="utf-8")
            self.assertIn("property bool dragging: false", source, style)
            self.assertIn("dragging: root.dragging", source, style)

    def test_the_shadow_is_dropped_for_the_motion_that_actually_costs(self):
        """`motionActive` had exactly one producer: the grip's elastic bow.

        Which is the one motion that does NOT resize the layer. The span
        animation - which reallocates the effect's FBO and re-runs a gaussian
        every frame, and which every "Size" row in settings triggers with no
        grip involved - ran with the shadow live throughout, because
        `resizeBow` is already zero by the time it starts.

        Both probes ASSIGN the flag rather than driving motion, so neither
        could see it. This pins the chain instead: the host publishes its own
        in-flight state, and it reaches every card.
        """
        host = (PLUGIN_ROOT.parent / "PluginWidget.qml").read_text(encoding="utf-8")
        node = (PLUGIN_ROOT.parent / "PluginNode.qml").read_text(encoding="utf-8")
        card = (DESIGN_SYSTEM / "widgets/WidgetCard.qml").read_text(encoding="utf-8")

        # The host knows: the drawn box differs from the settled one.
        self.assertIn("readonly property bool boxInMotion", host)
        self.assertIn("settledWidth", host.split("boxInMotion")[1][:300])
        self.assertIn("hostBoxInMotion: rootWidget.boxInMotion", host)
        self.assertIn("item.hostBoxInMotion = Qt.binding", node)
        # The card drops the shadow for the bow OR for the host's animation.
        self.assertIn("root.underTension || root.hostMotionActive", card)

        for directory in TOLD_ABOUT_THE_DRAG:
            wrapper = (PLUGIN_ROOT / directory / "Widget.qml").read_text(encoding="utf-8")
            self.assertIn("property bool hostBoxInMotion", wrapper, directory)
            self.assertIn("hostBoxInMotion", wrapper.split("hostBoxInMotion", 1)[1],
                          f"{directory}: declares the property but forwards it nowhere")

    def test_the_card_shadows_its_body_and_drops_it_while_moving(self):
        """The shadow comes off the BODY, and goes away during motion.

        Taken from the card as a whole it would put a shadow under every label
        and glyph inside it. And re-rendering a blurred copy of the body every
        frame of a morph is the expensive path - the same reason the frost is
        dropped for the duration of the motion.

        The card no longer spells the effect itself: five bundled widgets that
        are not cards need the same depth, so `WidgetElevation` owns the
        numbers and the card hands it the states. Both halves are checked here
        - what the card delegates, and what the shared piece does with it.
        """
        card = (DESIGN_SYSTEM / "widgets/WidgetCard.qml").read_text(encoding="utf-8")
        self.assertIn("WidgetElevation {", card)
        self.assertIn("id: bodySurface", card)
        body = card[card.index("id: bodySurface"):]
        for handed in ("shadowEnabled: root.shadowEnabled",
                       "motionActive: root.motionActive",
                       "dragging: root.dragging"):
            self.assertIn(handed, body[:400], "the card must hand over its state")
        # The content layer is a different one and must not gain a shadow.
        content = card[card.index("id: contentItem"):]
        self.assertNotIn("shadow", content.lower())

        elevation = (DESIGN_SYSTEM / "widgets/WidgetElevation.qml").read_text(
            encoding="utf-8")
        self.assertIn("shadowEnabled: true", elevation)
        self.assertIn("layer.enabled: root.shadowVisible", elevation)
        self.assertIn("root.shadowEnabled && !root.motionActive", elevation)
        # The layer clips at its item's bounds, and both the shadow and the
        # card's bowed canvas draw outside them, so the frame that carries the
        # layer is inset negatively and the body takes the bleed straight back.
        frame = elevation[elevation.index("id: shadowFrame"):]
        self.assertIn("anchors.margins: -root.bleed", frame[:400])
        self.assertIn("anchors.margins: root.bleed",
                      elevation[elevation.index("id: body"):][:300])

    def test_the_elevation_is_spelled_in_exactly_one_place(self):
        """`StyledDropShadow` was five hand-rolled shadows and two copies.

        The five older bundled widgets each carried one, at radius 8 against
        the design system's 12, at `colShadow` against `applyAlpha(colShadow,
        0.1)` - two components of the same name in two directories, neither
        agreeing with the other or with the card. They are folded onto
        `Appearance.elevation` through `WidgetElevation`, and the numbers may
        be read in that one file: a sixth copy is how this started.
        """
        self.assertFalse(list(ROOT.rglob("StyledDropShadow.qml")),
                         "the hand-rolled drop shadow came back")
        readers = set()
        for path in ROOT.rglob("*.qml"):
            if any(part in {".git", "tests"} for part in path.relative_to(ROOT).parts):
                continue
            if "Appearance.elevation." in path.read_text(encoding="utf-8"):
                readers.add(path.relative_to(ROOT).as_posix())
        self.assertEqual(
            readers,
            {"modules/common/plugins/designsystem/widgets/WidgetElevation.qml"},
            "the elevation numbers are read outside the component that owns them")

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
        # Swept, not named. The first version of this test listed three files
        # by hand and five verbatim copies survived in the very package it was
        # written for - MediaSeeker and MediaTransportButton, both added by the
        # same release. A check that enumerates its subjects only ever guards
        # the subjects someone remembered.
        swept = sorted(
            list((PLUGIN_ROOT / "nandoroid-media").glob("*.qml"))
            + [DESIGN_SYSTEM / "widgets/DesktopWeatherWidget.qml",
               DESIGN_SYSTEM / "widgets/DesktopCurrencyWidget.qml",
               DESIGN_SYSTEM / "widgets/DesktopMediaWidget.qml",
               # The two that stopped rebuilding per span. They join the sweep
               # rather than each carrying a private copy of the curve, which
               # is how a fifth tree would end up moving at its own speed
               # beside four that agree.
               PLUGIN_ROOT / "calendar/Widget.qml",
               PLUGIN_ROOT / "world-clock/Widget.qml"])
        self.assertGreaterEqual(len(swept), 8, "the sweep found nothing to check")
        carriers = 0
        for path in swept:
            source = path.read_text(encoding="utf-8")
            name = path.name
            self.assertNotIn("component TravelBehavior", source, name)
            self.assertNotIn("component FadeBehavior", source, name)
            # A whole-tier animation spelled inline. `ParallelAnimation`
            # members that name a target/property are a different thing and
            # SpanTravel cannot express them, so this looks for the Behavior
            # body's shape rather than the curve name alone.
            inline = ("NumberAnimation { duration: Appearance.animation.elementMove.duration"
                      in source)
            self.assertFalse(inline, f"{name} spells the span animation itself")
            if "SpanTravel {}" in source:
                carriers += 1
        self.assertGreaterEqual(carriers, 3,
                                "nothing in the sweep uses the shared spelling")
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
