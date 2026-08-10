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
        start, end = block_extent(self.source, "ContentSubsection {")
        section = self.source[start:end]
        self.assertIn("model: root.behaviourRows", section,
                      "every host row belongs inside the shared section")
        self.assertNotIn("model: root.widgetOptions", section,
                         "the plugin's own options must not be drawn inside "
                         "the host's section")

    def test_the_plugin_s_own_options_render_first_and_outside_the_section(self):
        start, end = block_extent(self.source, "ContentSubsection {")
        own = self.source.index("model: root.widgetOptions")
        self.assertLess(own, start,
                        "the widget's own options must render above the shared "
                        "section - they are what the page was opened for")

    def test_one_delegate_serves_every_repeater(self):
        """Two copies of the row delegate is how the groups drift apart."""
        self.assertEqual(self.source.count("id: optionRow"), 1)
        self.assertEqual(self.source.count("delegate: optionRow"),
                         self.source.count("Repeater {"),
                         "every group of rows draws through the one delegate")


if __name__ == "__main__":
    unittest.main(verbosity=2)
