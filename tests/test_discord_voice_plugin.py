import importlib.util
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "modules/common/plugins/bundled/discord-voice"
SERVICE = ROOT / "services/DiscordVoice.qml"
BRIDGE_PATH = ROOT / "scripts/discordVoice/discord_voice_bridge.py"

spec = importlib.util.spec_from_file_location("discord_voice_bridge", BRIDGE_PATH)
bridge_module = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(bridge_module)


class DiscordVoiceBridgeTests(unittest.TestCase):
    def test_voice_state_is_minimized_and_normalized(self):
        participant = bridge_module.Bridge.voice_user({
            "nick": "Speaker",
            "user": {"id": "42", "username": "user", "avatar": "hash", "email": "private"},
            "voice_state": {"self_mute": True, "deaf": False, "secret": "ignored"},
        })
        self.assertEqual(participant["nick"], "Speaker")
        self.assertTrue(participant["mute"])
        self.assertNotIn("email", participant)
        self.assertNotIn("secret", participant)

    def test_token_cache_is_owner_only(self):
        with tempfile.TemporaryDirectory() as directory:
            old_cache = os.environ.get("XDG_CACHE_HOME")
            os.environ["XDG_CACHE_HOME"] = directory
            try:
                bridge = bridge_module.Bridge()
                bridge.save_token("test-token")
                self.assertEqual(bridge.token(), "test-token")
                self.assertEqual(stat.S_IMODE(bridge.token_path.stat().st_mode), 0o600)
                bridge.clear_token()
                self.assertFalse(bridge.token_path.exists())
            finally:
                if old_cache is None:
                    os.environ.pop("XDG_CACHE_HOME", None)
                else:
                    os.environ["XDG_CACHE_HOME"] = old_cache

    def test_authorization_uses_non_intrusive_streamkit_prompt(self):
        source = BRIDGE_PATH.read_text()
        self.assertIn('"prompt": "none"', source)
        self.assertIn('emit("authorizing")', source)


class DiscordVoicePluginSafetyTests(unittest.TestCase):
    def test_manifest_has_bar_and_native_overlay_capabilities(self):
        manifest = json.loads((PLUGIN / "manifest.json").read_text())
        self.assertTrue(manifest["author"])
        self.assertEqual(manifest["barWidget"]["component"], "BarWidget.qml")
        self.assertNotIn("desktopWidget", manifest)
        self.assertIn("overlay-widget", manifest["capabilities"])
        self.assertIn("process", manifest["permissions"])
        self.assertIn("network", manifest["permissions"])

    def test_single_bridge_has_capped_backoff_and_no_running_binding(self):
        service = SERVICE.read_text()
        self.assertEqual(len(list(ROOT.glob("**/discord_voice_bridge.py"))), 1)
        self.assertIn("maxRestartAttempts: 5", service)
        self.assertIn("process-lifecycle: restart-safe", service)
        self.assertNotIn("running: true", service)
        self.assertIn("Math.min(30000", service)

    def test_native_bar_route_is_click_only_and_closes_on_focus_loss(self):
        host = (ROOT / "modules/ii/bar/BarContent.qml").read_text()
        self.assertIn('name === "plugin:discord_voice"', host)
        adapter = (ROOT / "modules/ii/bar/DiscordVoicePlugin.qml").read_text()
        self.assertIn("hoverEnabled: false", adapter)
        self.assertIn("cursorShape: Qt.PointingHandCursor", adapter)
        self.assertIn("HyprlandFocusGrab", adapter)

    def test_bundled_manifest_is_registered_in_plugin_manager(self):
        manager = (ROOT / "modules/common/plugins/PluginManager.qml").read_text()
        self.assertIn("discordVoiceManifestFile", manager)
        self.assertIn('bundled/discord-voice', manager)
        rebuild_list = manager[manager.index("function rebuildFromLoadedFiles"):
                               manager.index("function scanInstalledPlugins")]
        self.assertIn("discordVoiceManifestFile", rebuild_list)

    def test_super_g_overlay_is_registered_and_persistent(self):
        context = (ROOT / "modules/ii/overlay/OverlayContext.qml").read_text()
        chooser = (ROOT / "modules/ii/overlay/OverlayWidgetDelegateChooser.qml").read_text()
        persistent = (ROOT / "modules/common/Persistent.qml").read_text()
        overlay = ROOT / "modules/ii/overlay/discordVoice/DiscordVoiceOverlay.qml"
        self.assertIn('identifier: "discordVoice"', context)
        self.assertIn('enabled.includes("discord_voice")', context)
        self.assertIn('roleValue: "discordVoice"', chooser)
        self.assertIn("property JsonObject discordVoice", persistent)
        self.assertTrue(overlay.exists())
        self.assertIn("StyledOverlayWidget", overlay.read_text())
        content = (ROOT / "modules/ii/overlay/OverlayContent.qml").read_text()
        self.assertIn(".filter(widget => widget !== undefined)", content)

    def test_overlay_releases_exclusive_focus_before_authorizing(self):
        widget = (PLUGIN / "Widget.qml").read_text()
        self.assertIn("GlobalStates.overlayOpen = false", widget)
        self.assertIn("DiscordVoice.authorizeAfterFocusRelease()", widget)
        self.assertIn('text: DiscordVoice.status === "authorizing"', widget)
        service = SERVICE.read_text()
        self.assertIn("id: focusReleaseDelay", service)


if __name__ == "__main__":
    unittest.main()
