#!/usr/bin/env python3
"""Unit-level contracts that keep Docker UI allocation and process work bounded."""

from pathlib import Path
import json
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
DOCKER = ROOT / "modules/common/plugins/bundled/docker"


class DockerMemorySafetyTests(unittest.TestCase):
    def text(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def test_service_has_no_persistent_poll_or_stream(self):
        service = self.text("modules/common/plugins/bundled/docker/DockerService.qml")
        self.assertNotRegex(service, r"\brepeat\s*:\s*true")
        self.assertNotRegex(service, r"\bdocker\s+events\b")
        self.assertNotRegex(service, r"\b(events|monitor|subscribe)\b.*\brunning\s*:\s*true")
        self.assertEqual(service.count("Component.onCompleted: root.refresh()"), 1)

    def test_manifest_cannot_create_a_persistent_desktop_instance(self):
        manifest = json.loads((DOCKER / "manifest.json").read_text(encoding="utf-8"))
        self.assertNotIn("desktopWidget", manifest)
        self.assertFalse(any(
            option.get("key") == "pollingInterval"
            for option in manifest.get("options", [])
        ))

    def test_bar_adapter_is_content_sized_and_click_lazy(self):
        adapter = self.text("modules/imi/bar/DockerPlugin.qml")
        self.assertIn("contentLoader.item?.implicitWidth", adapter)
        self.assertNotRegex(adapter, r"(?m)^\s*(width|height)\s*:\s*implicit(?:Width|Height)")
        # A RippleButton since a click got a press: the popup opens from the
        # press action (click-lazy), the pointer cursor is the shared button's,
        # and the side padding is not named after the Control's FINAL property.
        self.assertIn("downAction:", adapter)
        self.assertIn("sidePadding: Appearance.spacing.space100", adapter)
        self.assertNotIn("property real horizontalPadding", adapter)
        self.assertRegex(adapter, r"Loader\s*\{[\s\S]*?active\s*:\s*root\.popupOpen")
        self.assertIn("hoverTarget: root", adapter)
        self.assertIn("onDismissRequested: root.popupOpen = false", adapter)

    def test_no_bar_popup_host_grabs_the_shared_surface(self):
        # Hyprland classifies an outside click by the surface's input region,
        # and the shared overlay's region is the card. A grab armed by a widget
        # while the card is still parked at 2*elevationMargin therefore treats
        # the next click anywhere as outside, closes the popup and destroys it -
        # which is why the Docker popup took several clicks to open. The grab
        # belongs to the overlay that owns the surface and knows when the card
        # has settled; a widget's job is to answer dismissRequested.
        for path in (
            "modules/imi/bar/DockerPlugin.qml",
            "modules/common/plugins/bundled/docker/DockerWidget.qml",
            "modules/imi/bar/DiscordVoicePlugin.qml",
        ):
            source = self.text(path)
            self.assertNotIn("HyprlandFocusGrab", source, path)
            self.assertNotIn("surfaceWindow", source, path)
            self.assertIn("onDismissRequested", source, path)

        systray = self.text("modules/imi/bar/SysTray.qml")
        self.assertNotIn("trayOverflowLayout.QsWindow", systray)
        self.assertIn("onDismissRequested: root.trayOverflowOpen = false", systray)

        overlay = self.text("modules/imi/bar/BarPopupOverlay.qml")
        self.assertIn("HyprlandFocusGrab {", overlay)
        self.assertIn("!overlayWindow.morphing", overlay)
        self.assertIn("onCleared: overlayWindow.current?.dismissRequested()", overlay)

    def test_popup_does_not_animate_layout_geometry(self):
        popup = self.text("modules/common/plugins/bundled/docker/DockerPopup.qml")
        self.assertNotRegex(popup, r"Behavior\s+on\s+implicit(?:Width|Height)")
        self.assertNotRegex(popup, r'property\s*:\s*["\'](?:width|height|implicitWidth|implicitHeight)["\']')
        # Non-Item objects declared at the popup root would be assigned to
        # StyledPopup's Item-only default property and invalidate the type, so
        # any animation has to sit inside the content tree. Stated over every
        # animation rather than over one named object, since the popup's own
        # enter animation went away when the shared card took the enter over.
        content_index = popup.index("id: panelContent")
        for match in re.finditer(r"\b\w*Animation\s*\{", popup):
            self.assertGreater(match.start(), content_index,
                               "animations belong inside the content tree, not at the popup root")

    def test_popup_uses_shared_components_not_its_own(self):
        """The plugin renders with the shell's M3E widgets rather than
        re-implementing buttons, tabs, cards and scrolling locally."""
        popup = self.text("modules/common/plugins/bundled/docker/DockerPopup.qml")
        for widget in ("SecondaryTabBar", "SecondaryTabButton", "StyledFlickable",
                       "StyledRectangle", "RippleButtonWithIcon", "IconToolbarButton",
                       "PagePlaceholder", "ExpandablePanel", "FlowButtonGroup",
                       "MaterialLoadingIndicator"):
            self.assertIn(widget, popup, f"{widget} should render part of the popup")
        # Bespoke re-implementations that these replaced.
        self.assertNotIn("ScrollBar.vertical: ScrollBar {}", popup)
        self.assertNotRegex(popup, r"component\s+ActionButton\s*:\s*RippleButton\b")
        self.assertNotRegex(popup, r"RotationAnimation\s+on\s+rotation")
        # Expansion animates through ExpandablePanel instead of toggling
        # visibility, which would make neighbouring cards jump
        # (docs/M3_GUIDELINES.md).
        self.assertNotRegex(popup, r"visible\s*:\s*\w+\.expanded")
        # The panel owns the motion contract; the popup must not re-declare it.
        self.assertNotIn("Behavior on implicitHeight", popup)
        self.assertIn("staggerStep", popup)

    def test_persistent_bar_uses_native_docker_adapter(self):
        bar = self.text("modules/imi/bar/BarContent.qml")
        self.assertNotIn("enableDockerForMemoryTest", bar)
        self.assertNotRegex(
            bar, r'name\s*===\s*["\']plugin:docker_plugin["\']\s*\)\s*return\s+false')
        # Which file draws a bar widget is one mapping both bars ask now, so
        # the pin follows it there - and covers the vertical bar for free,
        # where before Docker could have been pointed at the generic package
        # host there without this noticing. a47462fcc ("fix(verticalBar):
        # render plugin bar widgets instead of an empty stub").
        mapping = self.text("modules/imi/bar/bar_widget_source.js")
        self.assertRegex(
            mapping, r'["\']docker_plugin["\']\s*:\s*["\']DockerPlugin\.qml["\']')
        for bar_file in ("modules/imi/bar/BarContent.qml",
                         "modules/imi/verticalBar/VerticalBarContent.qml"):
            self.assertIn(
                "BarWidgetSource.fileNameFor", self.text(bar_file),
                f"{bar_file} resolves widget files itself again, so the "
                f"mapping pinned above is not the one it uses")

    def test_runtime_harness_exercises_repeated_popup_lifecycle(self):
        harness = self.text("DockerRuntimeTest.qml")
        self.assertGreaterEqual(harness.count("popupOpen = true"), 2)
        self.assertGreaterEqual(harness.count("popupOpen = false"), 2)
        # The adapter no longer arms a grab at all, so the harness has
        # nothing to switch off - it must also not reintroduce one, since a
        # focus grab needs a compositor this test does not have.
        self.assertNotIn("FocusGrab", harness)
        self.assertIn("Qt.exit(41)", harness)
        self.assertIn("Qt.exit(42)", harness)
        self.assertIn("onTriggered: Qt.exit(0)", harness)

        full_bar = self.text("DockerBarHostRuntimeTest.qml")
        self.assertIn("import qs.modules.imi.bar", full_bar)
        self.assertIn("BarContent {", full_bar)
        self.assertIn("onTriggered: Qt.exit(0)", full_bar)

        control = self.text("DockerBarControlRuntimeTest.qml")
        self.assertIn("suppressDockerForMemoryTest: true", control)


if __name__ == "__main__":
    unittest.main()
