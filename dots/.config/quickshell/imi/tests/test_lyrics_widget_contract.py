#!/usr/bin/env python3
"""Regression checks for the ported Nandoroid lyrics service/widget contract."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LyricsWidgetContractTests(unittest.TestCase):
    def test_service_declares_the_widget_activation_property(self):
        service = (ROOT / "services/LyricsService.qml").read_text(encoding="utf-8")
        self.assertIn("property bool desktopWidgetLyricsActive: false", service)
        # The widget's flag is one of two demands now: the sidebar view holds
        # a refcount, and the union gate is what arms and disarms the fetch.
        self.assertIn("property int sidebarLyricsRefs: 0", service)
        self.assertIn("onLyricsWantedChanged:", service)
        # Instrumental gaps become filler lines at parse time, threshold in
        # one place; the view draws them as the breathing note.
        self.assertIn("function withFillers", service)
        self.assertIn("root.withFillers(lines)", service)
        self.assertIn('property var slots: []', service)
        self.assertIn('root.status = "idle"', service)

    def test_desktop_widget_uses_the_shared_lyrics_component(self):
        # The widget's own five-line renderer was line-level with no word
        # sync; it now embeds the same Lyrics component the sidebar uses, so
        # the two views stay in step. The legacy slots renderer is gone, and
        # the component is loaded only while the lyrics page is shown (its
        # own refcount arms the service - the widget no longer writes the
        # activation flag itself).
        widget = (ROOT / "modules/common/plugins/designsystem/widgets/DesktopMediaWidget.qml").read_text(
            encoding="utf-8"
        )
        self.assertIn("import qs.modules.imi.mediaControls", widget)
        self.assertIn("sourceComponent: Lyrics {", widget)
        self.assertIn("active: root.viewLyrics", widget)
        # the legacy line-level renderer is retired
        self.assertNotIn('if (typeof slot === "string") return slot;', widget)
        self.assertNotIn('property: "flowOffset"', widget)
        self.assertNotIn("LyricsService.desktopWidgetLyricsActive = viewLyrics", widget)


if __name__ == "__main__":
    unittest.main()
