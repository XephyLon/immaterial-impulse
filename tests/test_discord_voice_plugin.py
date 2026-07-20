import importlib.util
import asyncio
import contextlib
import io
import json
import os
import stat
import tempfile
import unittest
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "modules/common/plugins/bundled/discordVoice"
SERVICE = ROOT / "services/DiscordVoice.qml"
BRIDGE_PATH = ROOT / "scripts/discordVoice/discord_voice_bridge.py"
COMPANION = ROOT / "scripts/discordVoice/vencord-companion"

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

    def test_authorization_timeout_cancels_nonce_and_rejects_socket(self):
        class Writer:
            closed = False
            def close(self):
                self.closed = True

        bridge = bridge_module.Bridge()
        writer = Writer()
        bridge.writer = writer
        bridge.current_path = "/run/user/1000/discord-ipc-0"
        bridge.pending["7"] = "AUTHORIZE"

        async def no_fallback():
            return False
        bridge.connect = no_fallback
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            asyncio.run(bridge.handle_authorization_timeout("7", bridge.current_path))

        self.assertNotIn("7", bridge.pending)
        self.assertTrue(writer.closed)
        self.assertIn("/run/user/1000/discord-ipc-0", bridge.authorization_failed_paths)
        self.assertIn("does not support voice authorization", output.getvalue())

    def test_candidate_paths_include_all_discord_socket_slots(self):
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/runtime"}):
            paths = bridge_module.Bridge.candidate_paths()
        self.assertIn("/runtime/discord-ipc-0", paths)
        self.assertIn("/runtime/discord-ipc-9", paths)
        self.assertIn("/runtime/app/com.discordapp.Discord/discord-ipc-0", paths)

    def test_fresh_vencord_state_is_accepted_and_stale_state_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": directory}):
                bridge = bridge_module.Bridge()
                state = {
                    "version": 1,
                    "backend": "vencord",
                    "timestamp": bridge_module.time.time() * 1000,
                    "user": {"id": "1", "username": "test"},
                    "channel": None,
                    "users": [],
                    "mute": False,
                    "deaf": False,
                }
                bridge.vencord_state_path.write_text(json.dumps(state))
                self.assertEqual(bridge.read_vencord_state()["backend"], "vencord")
                state["timestamp"] -= 5000
                bridge.vencord_state_path.write_text(json.dumps(state))
                self.assertIsNone(bridge.read_vencord_state())

    def test_companion_channel_refuses_symlinks_and_shared_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            victim = Path(directory) / "victim"
            victim.write_text("user data")
            os.chmod(victim, 0o644)
            runtime = Path(directory) / "runtime"
            runtime.mkdir()
            with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)}):
                bridge = bridge_module.Bridge()
                # A symlink planted at either path must not redirect the write
                # (which also chmodded the target before) or the read.
                os.symlink(victim, bridge.vencord_command_path)
                with self.assertRaises(OSError):
                    bridge.send_vencord_command(mute=True)
                self.assertEqual(victim.read_text(), "user data")
                self.assertEqual(stat.S_IMODE(victim.stat().st_mode), 0o644)
                os.symlink(victim, bridge.vencord_state_path)
                self.assertIsNone(bridge.read_vencord_state())

        # Without XDG_RUNTIME_DIR there is no user-private directory to use, so
        # the companion channel is disabled rather than moved to a shared one.
        with mock.patch.dict(os.environ, {}, clear=True):
            bridge = bridge_module.Bridge()
            self.assertIsNone(bridge.vencord_state_path)
            self.assertIsNone(bridge.vencord_command_path)
            self.assertIsNone(bridge.read_vencord_state())
            bridge.send_vencord_command(mute=True)

    def test_future_dated_vencord_state_expires(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": directory}):
                bridge = bridge_module.Bridge()
                bridge.vencord_state_path.write_text(json.dumps({
                    "version": 1, "backend": "vencord",
                    "timestamp": (bridge_module.time.time() + 9999) * 1000,
                }))
                self.assertIsNone(bridge.read_vencord_state())

    def test_companion_native_helper_has_no_shared_directory_fallback(self):
        native = (COMPANION / "native.ts").read_text()
        self.assertNotIn("tmpdir", native)
        self.assertIn("O_NOFOLLOW", native)

    def test_vencord_commands_are_owner_only(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": directory}):
                bridge = bridge_module.Bridge()
                bridge.send_vencord_command(mute=True)
                self.assertEqual(stat.S_IMODE(bridge.vencord_command_path.stat().st_mode), 0o600)
                self.assertEqual(json.loads(bridge.vencord_command_path.read_text()), {"mute": True})


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
        self.assertIn("pendingMessages = pendingMessages.concat([message])", service)
        self.assertIn("onStarted: root.flushPendingMessages()", service)

    def test_native_bar_route_is_click_only_and_closes_on_focus_loss(self):
        host = (ROOT / "modules/ii/bar/BarContent.qml").read_text()
        self.assertIn('name === "plugin:discord_voice"', host)
        adapter = (ROOT / "modules/ii/bar/DiscordVoicePlugin.qml").read_text()
        self.assertIn("hoverEnabled: false", adapter)
        self.assertIn("cursorShape: Qt.PointingHandCursor", adapter)
        self.assertIn("HyprlandFocusGrab", adapter)
        popup = (PLUGIN / "DiscordVoicePopup.qml").read_text()
        self.assertIn("root.pinnedOpen = false", popup)
        self.assertIn("DiscordVoice.authorizeAfterFocusRelease()", popup)

    def test_bundled_manifest_is_registered_in_plugin_manager(self):
        manager = (ROOT / "modules/common/plugins/PluginManager.qml").read_text()
        self.assertIn("discordVoiceManifestFile", manager)
        self.assertIn('bundled/discordVoice', manager)
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

    def test_vencord_companion_is_bundled_for_dual_backend_support(self):
        index = (COMPANION / "index.ts").read_text()
        native = (COMPANION / "native.ts").read_text()
        self.assertIn('name: "End4DiscordVoice"', index)
        self.assertIn("SelectedChannelStore", index)
        self.assertIn("toggleSelfMute", index)
        self.assertIn("end4-discord-voice-vencord.json", native)
        self.assertIn("mode: 0o600", native)
        self.assertIn('case "backend"', SERVICE.read_text())


if __name__ == "__main__":
    unittest.main()
