#!/usr/bin/env python3
"""Fail if rich text stops being an explicit, reviewed opt-in.

Installed plugin manifests are attacker-controlled, PluginValidator.js
type-checks `manifest.name` and nothing else, and StyledText is how manifest
strings (name, description, author, option labels, icons, placeholders) reach
the screen - so the render site is the only defence against `<img src=...>`
smuggled into a manifest field. The fix used to be applied one render site at
a time and was missed at least five times; the class is closed instead by
StyledText defaulting to Text.PlainText, which makes every future
manifest-field render site safe unless someone deliberately opts out.

That default only holds while three things stay true, none of which errors at
runtime when broken:

  1. Both StyledText definitions (mainline and the plugin design system's
     copy) keep `textFormat: Text.PlainText`.
  2. Every non-PlainText `textFormat:` in the tree is a reviewed opt-in. The
     allowlist below pins file -> expected count; a new rich-text site fails
     here until a reviewer confirms it never renders untrusted strings and
     adds it. Removing one must shrink the allowlist too, so it cannot rot
     into vacuous slack.
  3. ConfigTextArea keeps forcing the Basic Controls style's PlaceholderText
     child to PlainText - that Text lives inside Qt, where StyledText's
     default cannot reach, and PluginOptions feeds it `optionData.placeholder`
     straight from the manifest.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

STYLED_TEXT_DEFINITIONS = (
    "modules/common/widgets/StyledText.qml",
    "modules/common/plugins/designsystem/widgets/StyledText.qml",
)

PLACEHOLDER_GUARD_FILE = "modules/common/widgets/ConfigTextArea.qml"

# `textFormat: <value>` property assignments, wherever they sit on the line -
# an inline component (`StyledText { textFormat: Text.StyledText }`) is one
# too, and a line-anchored pattern was proved to miss it. The assignment must
# follow start-of-line, `{` or `;` so alias declarations (`property alias
# textFormat: item.textFormat`) stay excluded; comparisons ("textFormat ===")
# don't match. The value runs to `;`, `}`, an end-of-line comment, or EOL.
TEXT_FORMAT_ASSIGNMENT = re.compile(
    r"(?:^|[{;])\s*textFormat:\s*([^;}]+?)\s*(?:[;}]|//|$)")
PLAIN_VALUES = frozenset({"Text.PlainText", "TextEdit.PlainText"})

# Reviewed rich-text opt-ins: file -> number of non-PlainText textFormat
# assignments. Every entry either renders trusted shell-authored markup
# (tooltip/stopwatch/search-highlight strings built in this repo) or renders
# untrusted data through an escaping pipeline reviewed with it
# (NotificationUtils.processNotificationBody, SearchItem.highlightContent's
# escapeHtml). Before adding a file here, confirm no manifest- or
# notification-derived string reaches the site unescaped.
REVIEWED_RICH_TEXT_SITES = {
    "modules/common/plugins/designsystem/widgets/NotificationItem.qml": 2,
    "modules/common/plugins/designsystem/widgets/NotificationPopupItem.qml": 1,
    # Inline assignment (after `color: ...;` on one line); renders only the
    # shell-authored "Updated ..." template - Weather.status is a dead
    # reference, the qs.services Weather singleton declares no such property.
    "modules/common/plugins/designsystem/widgets/WeatherCard.qml": 1,
    "modules/common/widgets/NotificationItem.qml": 2,
    "modules/imi/overview/SearchItem.qml": 1,
    "modules/imi/screenTranslator/ScreenTextOverlay.qml": 1,
    "modules/imi/settings/pages/About.qml": 1,
    # The karaoke active line: every word passes root.escapeMarkup (&, <, >)
    # before the shell-authored <font color> wrapping - no provider string
    # reaches the site unescaped.
    "modules/imi/mediaControls/Lyrics.qml": 1,
    # base TextArea + the append-fade ghost twin, which renders the SAME
    # already-reviewed model string (textFormat mirrored) - no new source.
    "modules/imi/sidebarLeft/aiChat/MessageTextBlock.qml": 2,
    "modules/imi/sidebarLeft/anime/BooruResponse.qml": 1,
    "modules/imi/sidebarRight/SidebarRightContent.qml": 1,
    "modules/imi/sidebarRight/nightLight/NightLightDialog.qml": 2,
    "modules/imi/sidebarRight/pomodoro/Stopwatch.qml": 1,
}


def rich_optins_by_file():
    found = {}
    for path in sorted(ROOT.rglob("*.qml")):
        rel = str(path.relative_to(ROOT))
        if rel.startswith("tests/"):
            continue
        for line in path.read_text(errors="ignore").splitlines():
            for match in TEXT_FORMAT_ASSIGNMENT.finditer(line):
                if match.group(1) not in PLAIN_VALUES:
                    found[rel] = found.get(rel, 0) + 1
    return found


class RichTextOptInLint(unittest.TestCase):
    def test_styled_text_defaults_to_plain_text(self):
        for rel in STYLED_TEXT_DEFINITIONS:
            source = (ROOT / rel).read_text()
            self.assertRegex(
                source, r"(?m)^\s*textFormat:\s*Text\.PlainText",
                f"{rel} must default textFormat to Text.PlainText - without "
                "it, Text.AutoText renders manifest strings as markup and "
                "every StyledText render site is an injection site again")

    def test_rich_text_sites_are_reviewed(self):
        found = rich_optins_by_file()
        for rel, count in sorted(found.items()):
            expected = REVIEWED_RICH_TEXT_SITES.get(rel, 0)
            self.assertLessEqual(
                count, expected,
                f"{rel} has {count} non-PlainText textFormat assignment(s), "
                f"{expected} reviewed. A rich-text site renders markup from "
                "whatever string reaches it - confirm no manifest- or other "
                "attacker-controlled data flows there unescaped, then add it "
                f"to REVIEWED_RICH_TEXT_SITES in {Path(__file__).name}")

    def test_reviewed_allowlist_carries_no_dead_entries(self):
        found = rich_optins_by_file()
        for rel, expected in sorted(REVIEWED_RICH_TEXT_SITES.items()):
            self.assertEqual(
                found.get(rel, 0), expected,
                f"{rel} is allowlisted for {expected} rich-text site(s) but "
                f"has {found.get(rel, 0)} - shrink REVIEWED_RICH_TEXT_SITES "
                "so the slack cannot hide a future unreviewed opt-in")

    def test_config_text_area_pins_the_style_placeholder(self):
        source = (ROOT / PLACEHOLDER_GUARD_FILE).read_text()
        self.assertRegex(
            source,
            r"child\.textFormat\s*=\s*Text\.PlainText",
            f"{PLACEHOLDER_GUARD_FILE} must keep forcing the Basic style's "
            "PlaceholderText to PlainText: that Text lives inside Qt's style, "
            "StyledText's default cannot reach it, and PluginOptions feeds it "
            "optionData.placeholder straight from the manifest")


if __name__ == "__main__":
    unittest.main()
