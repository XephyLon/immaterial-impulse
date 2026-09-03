#!/usr/bin/env python3
"""Desktop widget shadows have one switch, and it sits at the one shadow.

The maintainer asked (2026-09-03) for a toggle to enable or disable desktop
widget shadows, on by default. `WidgetElevation` is the one shadow a widget
casts (AGENT.md), so the switch is one gate there - in `shadowVisible`,
beside the motion drop - rather than a flag every widget would have to pass
down and the next widget would forget. The setting is `plugins.shadows`,
defaulting to true so an upgrade changes nothing, and its row lives with the
other widget-wide settings on Settings > Plugins.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "modules/common/Config.qml"
ELEVATION = ROOT / "modules/common/plugins/designsystem/widgets/WidgetElevation.qml"
PAGE = ROOT / "modules/imi/settings/pages/PluginsPage.qml"


def code(path):
    return re.sub(r"//.*", "", path.read_text(encoding="utf-8"))


class WidgetShadowToggleTests(unittest.TestCase):
    def test_the_setting_defaults_on(self):
        plugins = code(CONFIG).split("property JsonObject plugins:", 1)[1].split("\n            }", 1)[0]
        self.assertIn("property bool shadows: true", plugins,
                      "plugins.shadows must exist and default on, so an upgrade changes nothing")

    def test_the_gate_is_at_the_one_shadow(self):
        elevation = code(ELEVATION)
        gate = re.search(r"readonly property bool shadowVisible:\s*(.*?)\n\n", elevation, re.S)
        self.assertIsNotNone(gate, "WidgetElevation.shadowVisible must exist")
        self.assertIn("Config.options.plugins.shadows", gate.group(1),
                      "the switch gates shadowVisible - the one place every widget's shadow is drawn")
        self.assertIn("root.shadowEnabled", gate.group(1))
        self.assertIn("!root.motionActive", gate.group(1))
        # No second gate anywhere else: a caller-side copy is the one that drifts.
        others = [p for p in (ROOT / "modules").rglob("*.qml")
                  if p != ELEVATION and "Config.options.plugins.shadows" in code(p) and p != PAGE]
        self.assertEqual(others, [], "plugins.shadows is read in one place")

    def test_the_row_is_an_intent_on_the_plugins_page(self):
        page = code(PAGE)
        row = re.search(r'ConfigSwitch \{[^}]*Translation\.tr\("Widget shadows"\)[^}]*\}', page, re.S)
        self.assertIsNotNone(row, "Settings > Plugins needs a Widget shadows switch")
        self.assertIn("checked: Config.options.plugins.shadows", row.group(0))
        self.assertIn("onToggleRequested: Config.options.plugins.shadows = !Config.options.plugins.shadows",
                      row.group(0), "ConfigSwitch writes back through onToggleRequested, never by assigning checked")


if __name__ == "__main__":
    unittest.main()
