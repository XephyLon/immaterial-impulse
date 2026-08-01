#!/usr/bin/env python3
"""Regression checks for the ported Nandoroid lyrics service/widget contract."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LyricsWidgetContractTests(unittest.TestCase):
    def test_service_declares_the_widget_activation_property(self):
        service = (ROOT / "services/LyricsService.qml").read_text(encoding="utf-8")
        self.assertIn("property bool desktopWidgetLyricsActive: false", service)
        self.assertIn("onDesktopWidgetLyricsActiveChanged:", service)
        self.assertIn('property var slots: []', service)
        self.assertIn('root.status = "idle"', service)

    def test_widget_accepts_service_string_slots(self):
        widget = (ROOT / "modules/common/plugins/designsystem/widgets/DesktopMediaWidget.qml").read_text(
            encoding="utf-8"
        )
        self.assertIn('if (typeof slot === "string") return slot;', widget)
        self.assertIn("No synchronized lyrics available", widget)
        self.assertNotIn("LyricsService.restartLyrics();", widget)
        self.assertIn("function onActiveIndexChanged()", widget)
        self.assertIn('property: "flowOffset"', widget)
        self.assertIn('property: "flowOpacity"', widget)
        self.assertIn('property: "flowScale"', widget)
        self.assertNotIn('property: "implicitHeight"', widget)


if __name__ == "__main__":
    unittest.main()
