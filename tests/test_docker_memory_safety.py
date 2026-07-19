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
        adapter = self.text("modules/ii/bar/DockerPlugin.qml")
        self.assertIn("contentLoader.item?.implicitWidth", adapter)
        self.assertNotRegex(adapter, r"(?m)^\s*(width|height)\s*:\s*implicit(?:Width|Height)")
        self.assertIn("hoverEnabled: false", adapter)
        self.assertIn("cursorShape: Qt.PointingHandCursor", adapter)
        self.assertIn("horizontalPadding: Appearance.spacing.space100", adapter)
        self.assertRegex(adapter, r"Loader\s*\{[\s\S]*?active\s*:\s*root\.popupOpen")
        self.assertIn("hoverTarget: root", adapter)
        self.assertIn("property bool useOutsideClickGrab: true", adapter)
        self.assertIn("HyprlandFocusGrab {", adapter)
        self.assertIn("popupFocus.windows = []", adapter)
        self.assertNotIn("windows: [root.QsWindow", adapter)

    def test_popup_does_not_animate_layout_geometry(self):
        popup = self.text("modules/common/plugins/bundled/docker/DockerPopup.qml")
        self.assertNotRegex(popup, r"Behavior\s+on\s+implicit(?:Width|Height)")
        self.assertNotRegex(popup, r'property\s*:\s*["\'](?:width|height|implicitWidth|implicitHeight)["\']')
        content_index = popup.index("id: panelContent")
        self.assertGreater(popup.index("id: popupEnter"), content_index)
        self.assertGreater(popup.index("id: viewTransition"), content_index)
        self.assertIn("Appearance.colors.colOnPrimary", popup)

    def test_persistent_bar_uses_native_docker_adapter(self):
        bar = self.text("modules/ii/bar/BarContent.qml")
        self.assertNotIn("enableDockerForMemoryTest", bar)
        self.assertNotRegex(
            bar, r'name\s*===\s*["\']plugin:docker_plugin["\']\s*\)\s*return\s+false')
        self.assertRegex(
            bar,
            r'if \(name === "plugin:docker_plugin"\)[\s\S]*?return Qt\.resolvedUrl\("\./DockerPlugin\.qml"\)',
        )

    def test_runtime_harness_exercises_repeated_popup_lifecycle(self):
        harness = self.text("DockerRuntimeTest.qml")
        self.assertGreaterEqual(harness.count("popupOpen = true"), 2)
        self.assertGreaterEqual(harness.count("popupOpen = false"), 2)
        self.assertIn("useOutsideClickGrab: false", harness)
        self.assertIn("Qt.exit(41)", harness)
        self.assertIn("Qt.exit(42)", harness)
        self.assertIn("onTriggered: Qt.exit(0)", harness)

        full_bar = self.text("DockerBarHostRuntimeTest.qml")
        self.assertIn("import qs.modules.ii.bar", full_bar)
        self.assertIn("BarContent {", full_bar)
        self.assertIn("onTriggered: Qt.exit(0)", full_bar)

        control = self.text("DockerBarControlRuntimeTest.qml")
        self.assertIn("suppressDockerForMemoryTest: true", control)


if __name__ == "__main__":
    unittest.main()
