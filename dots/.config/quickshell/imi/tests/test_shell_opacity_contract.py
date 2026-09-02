#!/usr/bin/env python3
"""One opacity for the blurred shell surfaces, and widgets that can follow it.

Every blurred shell surface - the bar, the sidebars, the dock, the settings
window, the cheatsheet - draws on colLayer0, which `Appearance` thins by the
background transparency. Settings > Quick's "Shell opacity" slider is that
amount inverted, inert while Automatic derives it from the wallpaper or while
transparency is off. Desktop widgets had a slider of their own; Settings >
Widgets' "Follow shell opacity" makes their panels take the shell's through
PluginState, the one place every widget's panel alpha already passes.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
QUICK = ROOT / "modules/imi/settings/pages/QuickConfig.qml"
WIDGETS = ROOT / "modules/imi/settings/pages/PluginsPage.qml"
STATE = ROOT / "modules/common/plugins/PluginState.qml"
CONFIG = ROOT / "modules/common/Config.qml"


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))


def block(text, start_pattern):
    match = re.search(start_pattern + r"(.*?)\n\s{12}\}", text, re.S)
    return match.group(1) if match else None


class ShellOpacitySliderTests(unittest.TestCase):
    def setUp(self):
        self.quick = strip_comments(QUICK.read_text(encoding="utf-8"))

    def test_the_slider_is_the_background_transparency_inverted(self):
        slider = block(self.quick, r'ConfigSlider \{(?=[^}]*Translation\.tr\("Shell opacity"\))')
        self.assertIsNotNone(slider, "Settings > Quick carries a Shell opacity slider")
        self.assertRegex(slider, r"value:\s*1 - Config\.options\.appearance\.transparency\.backgroundTransparency")
        self.assertRegex(slider, r"backgroundTransparency = rounded")
        self.assertIn("Math.round((1 - newValue) * 20) / 20", slider)

    def test_the_slider_is_inert_while_automatic_or_off(self):
        slider = block(self.quick, r'ConfigSlider \{(?=[^}]*Translation\.tr\("Shell opacity"\))')
        self.assertRegex(slider, r"enabled:\s*Config\.options\.appearance\.transparency\.enable && !Config\.options\.appearance\.transparency\.automatic")


class WidgetsFollowTests(unittest.TestCase):
    def setUp(self):
        self.widgets = strip_comments(WIDGETS.read_text(encoding="utf-8"))
        self.state = strip_comments(STATE.read_text(encoding="utf-8"))
        self.config = strip_comments(CONFIG.read_text(encoding="utf-8"))

    def test_the_option_exists_and_defaults_off(self):
        self.assertRegex(self.config, r"property bool followShellOpacity: false")

    def test_the_widgets_page_has_the_toggle_and_the_slider_yields_to_it(self):
        toggle = block(self.widgets, r'ConfigSwitch \{(?=[^}]*Translation\.tr\("Follow shell opacity"\))')
        self.assertIsNotNone(toggle, "Settings > Widgets carries a Follow shell opacity switch")
        self.assertRegex(toggle, r"checked:\s*Config\.options\.plugins\.followShellOpacity")
        slider = block(self.widgets, r'ConfigSlider \{(?=[^}]*Translation\.tr\("Blurred widget opacity"\))')
        self.assertRegex(slider, r"enabled:.*&& !Config\.options\.plugins\.followShellOpacity")
        self.assertRegex(slider, r"value:\s*Config\.options\.plugins\.followShellOpacity\s*\?\s*1 - Appearance\.backgroundTransparency")

    def test_plugin_state_hands_widgets_the_shells_opacity_when_following(self):
        self.assertRegex(self.state, r"readonly property real configuredBackgroundOpacity: Config\.options\.plugins\.followShellOpacity\s*\?\s*1 - Appearance\.backgroundTransparency\s*:\s*Config\.options\.plugins\.blurOpacity")
        self.assertRegex(self.state, r"baseOpacity === undefined \? root\.configuredBackgroundOpacity : baseOpacity")

    def test_no_widget_reads_the_widget_slider_directly(self):
        # The follow switch only works if every panel alpha passes PluginState.
        for path in ROOT.rglob("*.qml"):
            if "/tests/" in str(path) or path in (STATE, WIDGETS, CONFIG):
                continue
            self.assertNotIn("plugins.blurOpacity", strip_comments(path.read_text(encoding="utf-8", errors="replace")),
                             f"{path.relative_to(ROOT)} reads plugins.blurOpacity directly; go through PluginState.effectiveBackgroundOpacity")


if __name__ == "__main__":
    unittest.main()
