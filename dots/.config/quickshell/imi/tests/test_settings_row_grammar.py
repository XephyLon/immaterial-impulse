#!/usr/bin/env python3
"""The settings row grammar: the shared widgets that carry it, and the one
page that has adopted it.

The grammar is the set of row shapes the maintainer rated on the sibling fork
(docs/p3drovfx-feature-delta-2026-08-24.md and the 2026-08-27 trial notes):
a subsection header with a leading icon, a segmented single-choice row whose
every option carries an icon and a label, a computed live hint under such a
row, a toggle row with a leading icon chip, a dropdown with a leading icon and
a "(Recommended)" suffix on its default choice, a text field with a floating
label, and an (i) affordance on any row that has a rationale. It lives in the
existing widgets as opt-in properties rather than in new ones - the fork's
numbers are hand-typed, the grammar is what transfers - and it is applied to
ONE reference page, Settings > Capture, so the change stays reviewable. Other
pages follow in later PRs, and this file is where each adoption is pinned.

Two halves, both of which decay on their own:

1. The widgets take their values from Appearance's tokens and motion tiers,
   never from a literal. tests/lint_spacing.py holds the spacing axis and
   tests/lint_motion_tier_partial.py the half-taken tier; this holds the rest
   of the grammar's surface - radius, font size, colour, duration, curve - on
   the six files that carry it.
2. CaptureConfig.qml uses every piece. A page can lose one row's `iconChip`
   or a new option can arrive without its icon, and nothing about the page
   errors; the shape just stops being the grammar.

Static, because the widgets are StyledText-and-layout QML that qmltestrunner
cannot build (see tst_placeholder_fit.qml for why). The arithmetic behind the
quality hint is tst_record_bitrate.qml's.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WIDGETS = ROOT / "modules/common/widgets"
PAGES = ROOT / "modules/imi/settings/pages"
PAGE = PAGES / "CaptureConfig.qml"

# Which settings pages have adopted the grammar, and where each one's own
# adoption is checked. Capture is the reference and is checked in full below;
# a later adopter is a line here plus page-shaped checks wherever that page's
# other contracts already live, so this file does not accumulate one class per
# page while the reference stays the thing that defines the grammar.
#
# It is a RATCHET, both ways: a page carrying the grammar's opt-ins without an
# entry fails, and an entry whose page has dropped them fails too. Without the
# second direction the register is a list nobody rechecks; without the first,
# a page adopts the grammar and nothing holds it there.
ADOPTERS = {
    "CaptureConfig.qml": "this file",
    "PhoneConfig.qml": "tests/test_phone_tab_surface_contract.py",
}

GRAMMAR_WIDGETS = (
    "CatalogueRow.qml",
    "ConfigSwitch.qml",
    "ConfigSelectionArray.qml",
    "ConfigComboBox.qml",
    "ConfigTextArea.qml",
    "ContentSubsection.qml",
)

# Every settings-row control offers the (i) affordance, so a rationale never
# has to become a paragraph under the label.
INFO_WIDGETS = (
    "ConfigSwitch.qml",
    "ConfigSelectionArray.qml",
    "ConfigComboBox.qml",
    "ConfigTextArea.qml",
    "ConfigSpinBox.qml",
)


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def blocks(source: str, type_name: str, pattern: bool = False):
    """Every `TypeName { ... }` body in the source, braces matched.

    `type_name` is a literal unless `pattern` is set, which lets a caller sweep
    every `Behavior on <property>` with one expression."""
    out = []
    opener = type_name if pattern else re.escape(type_name)
    for match in re.finditer(r"\b" + opener + r"\s*\{", source):
        depth = 0
        for index in range(match.end() - 1, len(source)):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    out.append(source[match.start():index + 1])
                    break
    return out


class RowGrammarWidgetTests(unittest.TestCase):
    """The pieces exist, as opt-ins on the widgets that already draw rows."""

    def widget(self, name: str) -> str:
        return read(WIDGETS / name)

    def test_a_subsection_header_can_lead_with_an_icon(self):
        source = self.widget("ContentSubsection.qml")
        self.assertIn('property string icon: ""', source,
                      "ContentSubsection has no `icon` - a subsection header "
                      "cannot lead with a Material Symbol")
        self.assertRegex(source, r"MaterialSymbol\s*\{[^}]*text:\s*root\.icon",
                         "the subsection's icon property is declared but no "
                         "glyph draws it")

    def test_a_toggle_rows_icon_chip_is_opt_in(self):
        row = self.widget("CatalogueRow.qml")
        self.assertIn("property bool iconChip: false", row,
                      "CatalogueRow's icon chip must be declared and default "
                      "off: 159 ConfigSwitch call sites draw this row, and the "
                      "chip is adopted page by page")
        switch = self.widget("ConfigSwitch.qml")
        self.assertIn("property alias iconChip: catalogueRow.iconChip", switch,
                      "ConfigSwitch does not expose the chip, so no settings "
                      "page can turn it on")

    def test_the_chip_never_decides_the_rows_height(self):
        """CatalogueRow's rule: the row's height comes from its labels and its
        affordance, never from its leading glyph - the glyph wrapper reports
        width only. A chip that reported its height would stretch every row
        it sits in, which is the reflow the row's own docs forbid."""
        row = strip_comments(self.widget("CatalogueRow.qml"))
        glyph = [b for b in blocks(row, "Component") if "id: glyphIcon" in b]
        self.assertEqual(len(glyph), 1, "CatalogueRow's glyph component is gone")
        self.assertNotIn("implicitHeight", glyph[0],
                         "the glyph wrapper reports a height - the chip now "
                         "sizes the row")
        self.assertIn("root.iconChip", glyph[0],
                      "the glyph component does not draw the chip")

    def test_a_choice_row_has_a_hint_slot_and_an_info_affordance(self):
        source = self.widget("ConfigSelectionArray.qml")
        self.assertIn("property alias detailContent: detailRow.data", source,
                      "ConfigSelectionArray has no full-width slot under the "
                      "choice for a computed hint")
        self.assertRegex(source, re.compile(r"^ColumnLayout\s*\{", re.M), "the hint sits UNDER "
                         "the choice, so the root has to be a column")
        self.assertIn('property string infoText: ""', source)
        self.assertIn("InfoTooltipIcon {", source)

    def test_a_dropdowns_recommended_choice_is_marked_by_its_model(self):
        source = self.widget("ConfigComboBox.qml")
        self.assertIn("recommended", source,
                      "ConfigComboBox does not read a `recommended` flag off "
                      "its model entries")
        self.assertRegex(source, r'Translation\.tr\("[^"]*Recommended[^"]*"\)',
                         "the suffix is not a translated string")
        self.assertIn("import qs.services", source,
                      "Translation is a qs.services singleton and imports are "
                      "not transitive - without this the suffix is a "
                      "ReferenceError on every model change")
        self.assertIn('property string infoText: ""', source)
        self.assertIn("InfoTooltipIcon {", source)

    def test_a_text_field_can_float_its_label(self):
        source = self.widget("ConfigTextArea.qml")
        self.assertIn("property bool floatingLabel: false", source)
        self.assertIn('property string infoText: ""', source)
        self.assertIn("InfoTooltipIcon {", source)
        # A floated label leaves the row's label column empty, so the field
        # takes the row instead of sitting at fieldWidth beside a blank.
        self.assertRegex(source, r"Layout\.fillWidth:[^\n]*floatingLabel",
                         "the field does not fill the row when its label floats")
        # M3's filled text field is taller than the shell's compact one, and
        # the label needs the room to float into.
        self.assertRegex(source, r"fieldHeight:[^\n]*floatingLabel",
                         "the field height does not change for a floating label")

    def test_every_row_widget_offers_the_info_affordance(self):
        for name in INFO_WIDGETS:
            source = self.widget(name)
            self.assertIn('property string infoText: ""', source,
                          f"{name} has no infoText")
            reaches = "InfoTooltipIcon {" in source or "infoText: root.infoText" in source
            self.assertTrue(reaches, f"{name} declares infoText and draws nothing for it")


class TokensOnlyTests(unittest.TestCase):
    """The grammar's widgets read Appearance for every visual value.

    lint_spacing.py holds spacing; lint_motion_tier_partial.py holds a tier
    taken by half. This holds the rest on exactly the six files that carry the
    grammar: a radius, a font size, a colour, a duration, an easing curve.
    """

    # A dimension (implicitWidth, fieldHeight, charSize) is deliberately not
    # tokenized - docs/M3_GUIDELINES.md "Dimensions" - so it is not swept.
    RADIUS = re.compile(r"^\s*(?:\w+Radius|radius)\s*:\s*(.+)$", re.M)
    FONT_SIZE = re.compile(r"^\s*(?:font\.pixelSize|iconSize)\s*:\s*(.+)$", re.M)
    COLOR = re.compile(r"^\s*(?:\w*[cC]olor|\w*[cC]olour)\s*:\s*(.+)$", re.M)
    LITERAL_NUMBER = re.compile(r"(?<![\w.])\d+(?:\.\d+)?(?![\w.])")
    COLOR_LITERAL = re.compile(r'"#|Qt\.rgba\(|"(?!transparent")[a-z]+"')

    def sources(self):
        for name in GRAMMAR_WIDGETS:
            yield name, strip_comments(read(WIDGETS / name))

    def test_no_radius_or_font_size_is_a_literal(self):
        for name, source in self.sources():
            for pattern in (self.RADIUS, self.FONT_SIZE):
                for match in pattern.finditer(source):
                    value = match.group(1)
                    self.assertFalse(
                        self.LITERAL_NUMBER.search(value) and "Appearance." not in value
                        and "root." not in value and "height" not in value,
                        f"{name}: `{match.group(0).strip()}` is a literal, not a token")

    def test_no_colour_is_a_literal(self):
        for name, source in self.sources():
            for match in self.COLOR.finditer(source):
                self.assertFalse(
                    self.COLOR_LITERAL.search(match.group(1)),
                    f"{name}: `{match.group(0).strip()}` names a colour literal")

    def test_no_duration_or_curve_is_written_out(self):
        for name, source in self.sources():
            self.assertNotRegex(source, r"\bduration\s*:",
                                f"{name} writes a duration - take the tier whole")
            self.assertNotRegex(source, r"\bEasing\.",
                                f"{name} names a Qt easing curve")

    def test_every_behavior_takes_a_tier_whole(self):
        for name, source in self.sources():
            for body in blocks(source, r"Behavior on [\w.]+", pattern=True):
                self.assertRegex(
                    body, r"animation:\s*Appearance\.animation\.\w+\.\w+Animation\.createObject\(",
                    f"{name}: a Behavior does not take its tier's factory: "
                    f"{body.strip().splitlines()[0]}")

    def test_the_sweep_saw_the_grammars_surface(self):
        # A regex that stopped matching passes on an empty tree.
        radii = fonts = colors = behaviors = 0
        for _name, source in self.sources():
            radii += len(self.RADIUS.findall(source))
            fonts += len(self.FONT_SIZE.findall(source))
            colors += len(self.COLOR.findall(source))
            behaviors += len(blocks(source, r"Behavior on [\w.]+", pattern=True))
        self.assertGreaterEqual(radii, 3)
        self.assertGreaterEqual(fonts, 8)
        self.assertGreaterEqual(colors, 15)
        self.assertGreaterEqual(behaviors, 5)


class AdoptionRegisterTests(unittest.TestCase):
    """Who has adopted the grammar, in both directions."""

    # The chip is the opt-in no page carries by accident: it defaults off
    # precisely because 159 ConfigSwitch call sites draw that row and the
    # chip must not move any of them.
    MARKER = "iconChip: true"

    def test_every_registered_adopter_still_carries_the_grammar(self):
        for name in sorted(ADOPTERS):
            path = PAGES / name
            self.assertTrue(path.is_file(), f"{name} is registered as an adopter and is gone")
            self.assertIn(self.MARKER, read(path),
                          f"{name} is registered as an adopter and has dropped the "
                          f"grammar's icon chips")

    def test_a_page_that_adopted_the_grammar_is_in_the_register(self):
        unregistered = sorted(
            path.name for path in PAGES.glob("*.qml")
            if self.MARKER in read(path) and path.name not in ADOPTERS)
        self.assertEqual(unregistered, [], "these pages carry the row grammar but are "
                                           "not in ADOPTERS - add the line and say where "
                                           "the page's own adoption is checked")


class CaptureConfigAdoptionTests(unittest.TestCase):
    """The reference page uses every piece of the grammar."""

    @classmethod
    def setUpClass(cls):
        cls.source = read(PAGE)
        cls.code = strip_comments(cls.source)

    def test_every_toggle_row_carries_an_icon_chip(self):
        rows = blocks(self.code, "ConfigSwitch")
        self.assertGreaterEqual(len(rows), 8, "the page lost most of its switches")
        for row in rows:
            self.assertIn("iconChip: true", row,
                          f"a toggle row on the reference page has no icon chip:\n{row}")

    def test_every_choice_option_carries_an_icon_and_a_label(self):
        rows = blocks(self.code, "ConfigSelectionArray")
        self.assertGreaterEqual(len(rows), 2)
        for row in rows:
            options = re.search(r"options:\s*\[(.*?)\n\s*\]", row, re.S)
            self.assertIsNotNone(options, f"a choice row declares no options:\n{row}")
            entries = re.findall(r"\{[^{}]*\}", options.group(1))
            self.assertTrue(entries, "no option entries parsed")
            for entry in entries:
                self.assertRegex(entry, r"\bicon:\s*\"[a-z0-9_]+\"",
                                 f"an option on the reference page has no icon: {entry}")
                self.assertRegex(entry, r"\bdisplayName:\s*Translation\.tr\(",
                                 f"an option on the reference page has no label: {entry}")

    def test_the_quality_hint_is_computed_from_the_screen(self):
        self.assertIn('record_bitrate.js" as RecordBitrate', self.code,
                      "the page does not import the estimate's arithmetic")
        quality = [b for b in blocks(self.code, "ConfigSelectionArray")
                   if "screenRecord.quality" in b]
        self.assertEqual(len(quality), 1, "the quality row is gone")
        self.assertIn("detailContent:", quality[0], "the quality row has no hint under it")
        self.assertIn("RecordBitrate.estimateMbps(", quality[0])
        self.assertIn("RecordBitrate.effectiveFps(", quality[0],
                      "the hint's frame rate ignores the screen's refresh rate")
        self.assertIn("HyprlandData.monitors", self.code,
                      "the hint's screen does not come from hyprctl's monitor list")
        self.assertIn("QsWindow.window", self.code,
                      "the hint is not made for the screen the window is on")

    def test_the_hint_hides_rather_than_inventing_a_screen(self):
        # 1920x1080@60 as a fallback is a plausible number for a screen that
        # does not exist - the earlier draft did exactly that.
        for literal in ("1920", "1080", "refreshRate: 60"):
            self.assertNotIn(literal, self.code,
                             f"the page carries a placeholder screen ({literal})")

    def test_the_dropdown_marks_its_recommended_choice(self):
        combos = blocks(self.code, "ConfigComboBox")
        self.assertEqual(len(combos), 1, "the reference page has one dropdown, the codec")
        combo = combos[0]
        self.assertRegex(combo, r'buttonIcon:\s*"[a-z0-9_]+"', "the dropdown has no leading icon")
        self.assertEqual(combo.count("recommended: true"), 1,
                         "exactly one codec is the recommended one")
        self.assertIn("infoText:", combo,
                      "the codec's rationale (why no HDR entries) belongs on "
                      "the (i), not in a comment nobody on the page can read")

    def test_every_text_field_floats_its_label(self):
        fields = blocks(self.code, "ConfigTextArea")
        self.assertGreaterEqual(len(fields), 3)
        for field in fields:
            self.assertIn("floatingLabel: true", field,
                          f"a text field on the reference page keeps its label beside it:\n{field[:200]}")

    def test_every_subsection_leads_with_an_icon(self):
        subsections = blocks(self.code, "ContentSubsection")
        self.assertGreaterEqual(len(subsections), 5)
        for block in subsections:
            head = block[:400]
            self.assertRegex(head, r'icon:\s*"[a-z0-9_]+"',
                             f"a subsection on the reference page has no icon:\n{head}")

    def test_a_rationale_rides_the_info_affordance(self):
        self.assertGreaterEqual(self.code.count("infoText:"), 2,
                                "no row on the reference page uses the (i)")
        for match in re.finditer(r'description:\s*Translation\.tr\("([^"]+)"\)', self.code):
            self.assertLess(len(match.group(1)), 120,
                            "a paragraph under a label is a rationale, and a "
                            "rationale is the (i)'s: " + match.group(1)[:60])


if __name__ == "__main__":
    unittest.main(verbosity=1)
