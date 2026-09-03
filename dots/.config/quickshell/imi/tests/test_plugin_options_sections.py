#!/usr/bin/env python3
"""Source contract: a widget's own options and the host's rows are two groups.

`PluginOptions.qml` used to build one flat model - four synthesized host rows
(`Blur background`, `Lock position`, `Click through`, `Stay translucent`)
`.concat(manifest.options)` in front of whatever the plugin declared. Every
widget's settings page therefore opened with four identical switches, and the
two or three settings the user actually came for sat below them, reading as if
the plugin had declared the switches too.

The split is presentation only, so nothing at runtime notices if a later edit
concatenates the two lists again - the page still renders, just wrong again.
This is the greppable half: the plugin's own options render first and outside
the section, and every host row renders inside a `ContentSubsection` titled
"Widget behaviour".
"""
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
OPTIONS = ROOT / "modules/common/plugins/PluginOptions.qml"

SUBSECTION_TITLE = "Widget behaviour"


def without_comments(source):
    """Source with `//` comments dropped.

    A check that matches source text matches a commented-out line just as
    happily as a live one - which is exactly how a mutation that deletes a
    binding by commenting it out passes the check guarding that binding.
    Proven by planting that mutation; the first version of this file did not
    redden for it.
    """
    return re.sub(r"//[^\n]*", "", source)


def block_extent(source, opener):
    """[start, end) of the QML block introduced by `opener` ("Foo {")."""
    start = source.index(opener)
    depth = 0
    for index in range(start + len(opener) - 1, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return start, index + 1
    raise AssertionError(f"unbalanced braces after {opener!r}")


def host_section(source):
    """[start, end) of the host's behaviour ContentSubsection - the one whose
    id is behaviourSection. Not the first `ContentSubsection {` in the file:
    since option groups render under a subsection of their own (a `group` in
    the manifest), that opener appears inside the grouped-run component first."""
    anchor = source.index("id: behaviourSection")
    start = source.rfind("ContentSubsection {", 0, anchor)
    assert start != -1, "behaviourSection is not a ContentSubsection"
    offset, end = block_extent(source[start:], "ContentSubsection {")
    return start + offset, start + end


class TheTwoGroupsStaySeparate(unittest.TestCase):
    def setUp(self):
        self.source = OPTIONS.read_text(encoding="utf-8")

    def test_the_two_models_are_declared_separately(self):
        self.assertRegex(
            self.source,
            r"readonly property var widgetOptions:\s*manifest\.options \|\| \[\]",
            "the plugin's own options must be their own model")
        self.assertRegex(
            self.source,
            r"readonly property var behaviourRows:\s*hasBlurSurface \?",
            "the host's rows must be their own model")

    def test_the_host_rows_are_never_concatenated_onto_the_plugin_s(self):
        """The exact shape this split removed."""
        self.assertIsNone(
            re.search(r"\.concat\(\s*manifest\.options", self.source),
            "host rows are concatenated in front of the plugin's options again")
        self.assertIsNone(
            re.search(r"\.concat\(\s*root\.widgetOptions", self.source),
            "host rows are concatenated onto the plugin's options again")
        self.assertIsNone(
            re.search(r"widgetOptions[^\n]*behaviourRows", self.source),
            "the two models must not be joined into one")

    def test_a_subsection_holds_the_host_rows(self):
        self.assertIn(f'title: Translation.tr("{SUBSECTION_TITLE}")', self.source,
                      "the host rows need a titled ContentSubsection")
        start, end = host_section(self.source)
        section = self.source[start:end]
        self.assertIn("model: root.behaviourRows", section,
                      "every host row belongs inside the shared section")
        self.assertNotIn("model: root.widgetOptions", section,
                         "the plugin's own options must not be drawn inside "
                         "the host's section")

    def test_the_plugin_s_own_options_render_first_and_outside_the_section(self):
        start, end = host_section(self.source)
        own = self.source.index("model: root.optionRuns")
        self.assertLess(own, start,
                        "the widget's own options must render above the shared "
                        "section - they are what the page was opened for")

    def test_one_delegate_serves_every_group_of_rows(self):
        """Two copies of the row delegate is how the groups drift apart.

        The host's booleans are a toggle bar rather than rows now, so the
        count is against the groups still drawn AS rows - the plugin's own
        options and the size row - rather than against every Repeater in the
        file.
        """
        self.assertEqual(self.source.count("id: optionRow"), 1)
        # The plugin's own options come in runs now - grouped under a heading
        # or plain - and both run shapes draw their rows through the delegate,
        # as does the size row.
        for model in ("runLoader.modelData.options", "root.sizeRows"):
            self.assertRegex(
                self.source,
                rf"model: {re.escape(model)}\s*\n\s*delegate: optionRow",
                f"{model} no longer draws through the shared row delegate")
        self.assertIn("model: root.packLines(root.visibleOptions(runLoader.modelData))", self.source,
                      "a group's lines are packed from its visible options")
        self.assertEqual(self.source.count("delegate: optionRow"), 2,
                         "the ungrouped run and the size row draw through the one delegate")
        # A group's packed lines place the same row item directly - one
        # OptionRowItem, two ways in - and never on plates: surfaces around
        # rows that are already controls read as one more list.
        self.assertEqual(self.source.count("component OptionRowItem: Loader"), 1)
        self.assertNotIn("GroupedList", self.source[self.source.index("model: root.optionRuns"):self.source.index("id: behaviourSection")])
        self.assertIn("function packLines(options)", self.source)
        self.assertRegex(self.source, r'sourceComponent: modelData\.kind === "pair" \? pairLine : singleLine')
        self.assertRegex(self.source, r"stackChoices: true")


class TheHostBooleansAreAToggleBar(unittest.TestCase):
    """Six booleans were six full-width switch rows - icon, label and track per
    bit, 212px of a popup whose scarce axis is vertical. They are one wrapping
    bar of icon toggles now (72px measured, five of the six rows' worth
    reclaimed), which only works while three things hold: the toggles are
    composed from the existing control rather than hand-rolled, a click stays
    an intent, and every glyph is still named by something.
    """

    def setUp(self):
        self.source = without_comments(OPTIONS.read_text(encoding="utf-8"))
        start, end = host_section(self.source)
        self.section = self.source[start:end]

    def test_the_bar_wraps(self):
        """A row of six 40px toggles fits the settings card today and does not
        fit every surface this page could end up on. `FlowButtonGroup` is a
        Flow - a plain RowLayout would push the last toggles off the edge."""
        self.assertIn("FlowButtonGroup {", self.section,
                      "the toggles need a container that wraps")
        bar_start, bar_end = block_extent(self.section, "FlowButtonGroup {")
        bar = self.section[bar_start:bar_end]
        self.assertIn("model: root.behaviourRows", bar,
                      "every host boolean belongs in the one wrapping bar")

    def test_the_toggle_is_composed_not_written(self):
        """`IconToolbarButton` is already an icon-only button whose `toggled`
        container states are M3's selected/unselected pair, and the
        `RippleButton` under it already owns the pointer shape and the ONE
        application of the shared interaction motion. A hand-rolled control
        here would have to re-earn all three."""
        self.assertIn("component BehaviourToggle: IconToolbarButton", self.source)

    def test_the_toggles_add_no_motion_of_their_own(self):
        """`lint_interaction_motion_double` and `lint_disabled_opacity` both
        fail on this, and both key on an idiom - so pin it here too, where the
        reason is written down."""
        start, end = block_extent(self.source, "component BehaviourToggle: IconToolbarButton {")
        toggle = self.source[start:end]
        for doubled in ("scale:", "opacity:"):
            self.assertNotIn(doubled, toggle,
                             "the control already applies the interaction "
                             "model; a second one composites with it")

    def test_a_click_is_still_an_intent(self):
        """The ConfigSwitch rule survives the control swap: `toggled` is a
        pure binding on the store and the handler flips the value at its
        source. An assignment to `toggled` would destroy that binding and
        detach the toggle from what it displays, exactly as #158 did."""
        self.assertIsNone(
            re.search(r"\btoggled\s*=(?![=~])", self.source),
            "a toggle assigns to `toggled` - that is the binding destroyed by hand")
        self.assertIn("toggled: PluginState.option(root.manifest.id, modelData.key, "
                      "modelData.default)", self.section)
        self.assertIn("PluginState.setOption(root.manifest.id, modelData.key,", self.section)
        self.assertIn("toggled: PluginState.presetPersisted(root.manifest.id)", self.section)
        self.assertIn("PluginState.setPresetPersist(root.manifest.id,", self.section)

    def test_no_host_boolean_is_a_row_any_more(self):
        """The preset-persist switch was the sixth of them and the only one
        not synthesized into `behaviourRows`; leaving it as a row would put a
        full-width switch beside a bar of toggles that mean the same kind of
        thing."""
        self.assertNotIn("ConfigSwitch", self.section)

    def test_every_toggle_carries_the_name_its_glyph_cannot(self):
        """A pin, a grid, a lock, a hand, a droplet and a frame are not
        self-evident. The caption below the bar names whichever one the pointer
        is over, so a toggle with no `label` is an unlabelable control."""
        self.assertIn("label: behaviourSection.presetPersistLabel", self.section)
        self.assertIn("label: modelData.label", self.section)
        self.assertIn("behaviourSection.hoveredLabel = toggle.label", self.source)

    def test_the_caption_falls_back_to_what_is_on(self):
        """Off-hover the caption answers the other question the six labels
        used to answer for free: which of these are on. Selected-state colour
        answers it too, but only once six glyphs have been learned."""
        self.assertIn("readonly property string enabledLabels", self.section)
        self.assertIn("behaviourSection.hoveredLabel.length > 0", self.section)
        self.assertIn("behaviourSection.enabledLabels.length > 0", self.section)

    def test_the_hover_label_is_cleared_only_by_the_toggle_that_wrote_it(self):
        """A pointer crossing from one toggle to the next delivers the leave
        and the enter in an order nothing here controls, so an unconditional
        clear on a leave blanks the label the enter just wrote."""
        self.assertIn(
            "else if (behaviourSection.hoveredLabel === toggle.label)", self.source)



class ChoiceGatingTests(unittest.TestCase):
    """A shape choice may be offered and not pickable at once.

    Custom Image's "None" exists only while the background is transparent -
    an opaque plate with no mask is a bare rectangle nothing else in the
    grid can produce. The gate is the choice's own `enabledWhen`, evaluated
    with the same rule spelling rows use, and the widget restores the last
    real shape when transparency goes away under a picked "None"."""

    def test_the_renderer_derives_disabled_choices_from_the_rule(self):
        src = (ROOT / "modules/common/plugins/PluginOptions.qml").read_text(encoding="utf-8")
        self.assertIn("disabledOptions:", src)
        self.assertRegex(src, r"disabledOptions:[\s\S]{0,400}OptionVisibility\.rule\(choice\.enabledWhen")

    def test_the_shape_array_dims_and_ignores_disabled_choices(self):
        src = (ROOT / "modules/common/widgets/ConfigSelectionShapeArray.qml").read_text(encoding="utf-8")
        self.assertIn("property list<string> disabledOptions", src)
        self.assertRegex(src, r"enabled:\s*!choiceDisabled")

    def test_none_is_gated_on_transparency_in_the_manifest(self):
        import json as _json
        manifest = _json.loads((ROOT / "modules/common/plugins/bundled/custom-image/manifest.json").read_text(encoding="utf-8"))
        shape = next(o for o in manifest["options"] if o["key"] == "shape")
        none = next(c for c in shape["choices"] if c["value"] == "None")
        self.assertEqual(none["enabledWhen"], {"key": "transparentBackground", "equals": True})

    def test_the_widget_drops_none_when_opacity_returns(self):
        src = (ROOT / "modules/common/plugins/bundled/custom-image/Widget.qml").read_text(encoding="utf-8")
        self.assertIn("dropNoneIfOpaque", src)
        self.assertIn("shapeBeforeNone", src)
        self.assertRegex(src, r"Component\.onCompleted:\s*root\.dropNoneIfOpaque\(\)")


if __name__ == "__main__":
    unittest.main(verbosity=2)
