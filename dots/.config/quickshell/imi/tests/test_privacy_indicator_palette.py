#!/usr/bin/env python3
"""The privacy indicator is danger-red in both themes.

It is an alarm: an app is on the microphone, the camera or the screen. M3's
error role flips saturation with the theme - the dark theme's colError is a
pastel pink and its errorContainer the deep red, the light theme the other
way round - so colError alone was a pink pill with a dark glyph in the dark
theme and read as decoration. Appearance's alarm pair picks the saturated
member and its on-colour in either theme; the indicator wears that pair under
every bar style, and hover is a colour rather than a dim.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "modules/imi/bar/PrivacyIndicator.qml"
APPEARANCE = ROOT / "modules/common/Appearance.qml"


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))


class AlarmPairTests(unittest.TestCase):
    def test_the_alarm_pair_is_the_saturated_member_in_either_theme(self):
        appearance = strip_comments(APPEARANCE.read_text(encoding="utf-8"))
        self.assertRegex(appearance, r"property color colAlarm: m3colors\.darkmode \? m3colors\.m3errorContainer : m3colors\.m3error")
        self.assertRegex(appearance, r"property color colOnAlarm: m3colors\.darkmode \? m3colors\.m3onErrorContainer : m3colors\.m3onError")
        self.assertRegex(appearance, r"property color colAlarmHover: m3colors\.darkmode \? colErrorContainerHover : colErrorHover")


class PrivacyIndicatorTests(unittest.TestCase):
    def setUp(self):
        self.src = strip_comments(SOURCE.read_text(encoding="utf-8"))

    def test_it_wears_the_alarm_pair_under_every_style(self):
        self.assertRegex(self.src, r"pillColor: root\.containsMouse \? Appearance\.colors\.colAlarmHover : Appearance\.colors\.colAlarm")
        self.assertRegex(self.src, r"onColor: Appearance\.colors\.colOnAlarm")
        self.assertNotIn("isMaterial", self.src, "the alarm does not change with the bar style")

    def test_it_is_never_the_accent_or_the_pastel_pair(self):
        for token in ("colPrimary", "colPrimaryContainer", "colOnPrimaryContainer", "colError\b", "colOnError\b"):
            self.assertNotRegex(self.src, r"Appearance\.colors\." + token, f"{token} is not the alarm")

    def test_hover_is_a_colour_not_a_dim(self):
        self.assertNotIn("0.88", self.src)
        self.assertRegex(self.src, r"Behavior on color \{\s*animation: Appearance\.animation\.\w+\.colorAnimation\.createObject\(this\)")


if __name__ == "__main__":
    unittest.main()
