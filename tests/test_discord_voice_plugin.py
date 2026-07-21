import importlib.util
import asyncio
import contextlib
import gc
import io
import json
import os
import stat
import tempfile
import unittest
import warnings
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

    def test_vencord_socket_pushes_state_and_returns_commands(self):
        class Reader:
            def __init__(self, line):
                self.lines = [line, b""]
            async def readline(self):
                return self.lines.pop(0)

        class Writer:
            def __init__(self):
                self.output = b""
                self.closed = False
            def is_closing(self): return self.closed
            def write(self, data): self.output += data
            async def drain(self): pass
            def close(self): self.closed = True
            async def wait_closed(self): pass

        async def scenario(directory):
            with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": directory}):
                bridge = bridge_module.Bridge()
                state = {"version": 1, "backend": "vencord", "user": {"id": "1"},
                         "channel": None, "users": [], "mute": False, "deaf": False}
                line = (json.dumps({"type": "state", "state": state}) + "\n").encode()
                async def no_fallback():
                    return False
                # candidate_paths() probes /tmp as well as XDG_RUNTIME_DIR, so
                # the temporary directory alone does not keep the disconnect
                # path away from a real Discord socket.
                bridge.connect = no_fallback
                writer = Writer()
                bridge.vencord_writer = writer
                bridge.apply_vencord_state(state)
                self.assertTrue(bridge.vencord_active)
                await bridge.send_vencord_command(mute=True)
                self.assertEqual(json.loads(writer.output), {"type": "command", "mute": True})
                # The parser accepts the same newline-delimited state frame.
                await bridge.handle_vencord_client(Reader(line), Writer())

        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            asyncio.run(scenario(directory))

    def test_companion_socket_refuses_symlinks_and_shared_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            victim = Path(directory) / "victim"
            victim.write_text("user data")
            runtime = Path(directory) / "runtime"
            runtime.mkdir()
            with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)}):
                bridge = bridge_module.Bridge()
                os.symlink(victim, bridge.vencord_socket_path)
                with contextlib.redirect_stdout(io.StringIO()):
                    asyncio.run(bridge.start_vencord_server())
                self.assertIsNone(bridge.vencord_server)
                self.assertEqual(victim.read_text(), "user data")

        with mock.patch.dict(os.environ, {}, clear=True):
            bridge = bridge_module.Bridge()
            self.assertIsNone(bridge.vencord_socket_path)
            asyncio.run(bridge.start_vencord_server())
            self.assertIsNone(bridge.vencord_server)

    def test_companion_socket_is_private_from_the_moment_it_is_bound(self):
        async def scenario(runtime):
            with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": runtime}):
                bridge = bridge_module.Bridge()
                await bridge.start_vencord_server()
                try:
                    mode = stat.S_IMODE(bridge.vencord_socket_path.stat().st_mode)
                    self.assertEqual(mode, 0o600)
                    self.assertIsNotNone(bridge.vencord_socket_inode)
                finally:
                    bridge.vencord_server.close()
                    await bridge.vencord_server.wait_closed()

        with tempfile.TemporaryDirectory() as runtime, contextlib.redirect_stdout(io.StringIO()):
            # A permissive umask must not widen the socket even briefly.
            previous = os.umask(0o000)
            try:
                asyncio.run(scenario(runtime))
            finally:
                os.umask(previous)
        # The mode must come from the bind, not from a later chmod that could
        # be aimed at a path something else has since swapped in.
        self.assertNotIn("os.chmod(self.vencord_socket_path", BRIDGE_PATH.read_text())

    def test_companion_disconnect_releases_its_transport(self):
        # close() only requests a shutdown. A handler that returns without
        # awaiting wait_closed() leaves the socket alive until the garbage
        # collector runs, which is what reported it as an unclosed
        # StreamWriter. Asserting the await is the contract; asserting the
        # absence of the warning is not, because a still-running event loop
        # completes the close on its own and hides the difference.
        class Writer:
            def __init__(self):
                self.closed = False
                self.awaited = False
            def is_closing(self): return self.closed
            def write(self, data): pass
            async def drain(self): pass
            def close(self): self.closed = True
            async def wait_closed(self): self.awaited = True

        class Reader:
            async def readline(self): return b""

        async def scenario():
            bridge = bridge_module.Bridge()

            async def no_fallback():
                return False
            bridge.connect = no_fallback
            writer = Writer()
            await bridge.handle_vencord_client(Reader(), writer)
            return writer

        with contextlib.redirect_stdout(io.StringIO()):
            writer = asyncio.run(scenario())
        self.assertTrue(writer.closed)
        self.assertTrue(writer.awaited,
                        "handler returned before the transport was released")

    def test_companion_transport_is_clean_over_a_real_socket(self):
        state = {"version": 1, "backend": "vencord", "user": {"id": "1"},
                 "channel": None, "users": [], "mute": False, "deaf": False}

        async def scenario(runtime):
            with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": runtime}):
                bridge = bridge_module.Bridge()

                async def no_fallback():
                    return False
                # Keep the disconnect path off this machine's real Discord socket.
                bridge.connect = no_fallback
                await bridge.start_vencord_server()
                try:
                    _, writer = await asyncio.open_unix_connection(
                        bridge.vencord_socket_path)
                    writer.write((json.dumps({"type": "state", "state": state}) + "\n").encode())
                    await writer.drain()
                    await asyncio.sleep(0.05)
                    writer.close()
                    await writer.wait_closed()
                    await asyncio.sleep(0.05)
                    # The handler ran to completion and let go of the peer.
                    self.assertIsNone(bridge.vencord_writer)
                finally:
                    bridge.vencord_server.close()
                    await bridge.vencord_server.wait_closed()

        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            with tempfile.TemporaryDirectory() as runtime, \
                    contextlib.redirect_stdout(io.StringIO()):
                asyncio.run(scenario(runtime))
            gc.collect()
        leaked = [str(entry.message) for entry in caught
                  if issubclass(entry.category, ResourceWarning)]
        self.assertEqual(leaked, [])

    def test_wedged_companion_cannot_stall_the_bridge_command_loop(self):
        class HangingWriter:
            def __init__(self):
                self.closed = False
            def is_closing(self): return self.closed
            def write(self, data): pass
            async def drain(self): await asyncio.sleep(3600)
            def close(self): self.closed = True
            async def wait_closed(self): pass

        async def scenario():
            bridge = bridge_module.Bridge()
            writer = HangingWriter()
            bridge.vencord_writer = writer
            bridge_module.COMPANION_WRITE_TIMEOUT = 0.05
            await asyncio.wait_for(bridge.send_vencord_command(mute=True), 2)
            # Dropped rather than waited on, so later stdin commands still run.
            self.assertTrue(writer.closed)

        original = bridge_module.COMPANION_WRITE_TIMEOUT
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                asyncio.run(scenario())
        finally:
            bridge_module.COMPANION_WRITE_TIMEOUT = original

    def test_malformed_frame_does_not_end_a_working_companion_session(self):
        class Reader:
            def __init__(self, lines): self.lines = list(lines)
            async def readline(self):
                return self.lines.pop(0) if self.lines else b""

        class Writer:
            def __init__(self): self.closed = False
            def is_closing(self): return self.closed
            def write(self, data): pass
            async def drain(self): pass
            def close(self): self.closed = True
            async def wait_closed(self): pass

        state = {"version": 1, "backend": "vencord", "user": {"id": "1"},
                 "channel": None, "users": [], "mute": False, "deaf": False}
        good = (json.dumps({"type": "state", "state": state}) + "\n").encode()

        async def scenario():
            bridge = bridge_module.Bridge()

            async def no_fallback():
                return False
            # End-of-stream falls back to Discord's RPC. Unstubbed, and with
            # XDG_RUNTIME_DIR left alone, candidate_paths resolves to this
            # machine's real discord-ipc socket and the test opens it.
            bridge.connect = no_fallback
            # Garbage first: the valid frame behind it must still be applied.
            await bridge.handle_vencord_client(Reader([b"{not json\n", good]), Writer())

        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            asyncio.run(scenario())
        emitted = [json.loads(line)["type"] for line in output.getvalue().splitlines() if line]
        # vencord_active is torn down by the end-of-stream path, so the proof
        # that the good frame survived the bad one is what reached the shell.
        self.assertIn("voice_channel", emitted)
        self.assertLess(emitted.index("voice_channel"), emitted.index("disconnected"))

    def test_companion_failure_does_not_masquerade_as_an_auth_prompt(self):
        bridge = BRIDGE_PATH.read_text()
        service = (ROOT / "services/DiscordVoice.qml").read_text()
        self.assertIn('emit("companion_error"', bridge)
        self.assertNotIn('emit("error", message="Refusing unsafe', bridge)
        # `error` drives the UI into an Authorize button the user cannot act
        # on; a companion fault leaves Discord's own RPC backend usable.
        self.assertIn('case "companion_error": errorMessage', service)
        self.assertIn('case "error":', service)

    def test_socket_cleanup_cannot_remove_a_successor_bridge_socket(self):
        bridge = BRIDGE_PATH.read_text()
        self.assertIn("vencord_socket_inode", bridge)
        self.assertIn("st_ino == bridge.vencord_socket_inode", bridge)

    def test_companion_native_helper_has_no_shared_directory_fallback(self):
        native = (COMPANION / "native.ts").read_text()
        index = (COMPANION / "index.ts").read_text()
        bridge = BRIDGE_PATH.read_text()
        self.assertNotIn("tmpdir", native)
        self.assertIn("createConnection", native)
        self.assertIn("nextCommand", native)
        self.assertIn("asyncio.start_unix_server", bridge)
        self.assertNotIn("vencord_monitor", bridge)
        self.assertNotIn("read_vencord_state", bridge)
        self.assertNotIn("readCommands", index)
        self.assertIn("await Native.nextCommand()", index)
        self.assertIn("setInterval(() => void publish(), 5000)", index)
        # A partial line left by a dropped connection must not corrupt the
        # first command of the next one.
        self.assertIn('input = "";', native)
        # Coalescing without a trailing re-publish would leave the shell on
        # stale state until the next heartbeat, five seconds later.
        self.assertIn("pending = true;", index)
        self.assertIn("} while (pending);", index)


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
        self.assertIn("end4-discord-voice-vencord.sock", native)
        self.assertIn("nextCommand", native)
        self.assertIn('case "backend"', SERVICE.read_text())

    def test_overlay_has_expressive_voice_controls_and_column_mode(self):
        widget = (PLUGIN / "Widget.qml").read_text()
        manifest = json.loads((PLUGIN / "manifest.json").read_text())
        options = {option["key"]: option for option in manifest["options"]}
        self.assertEqual(options["overlayLayout"]["default"], "row")
        self.assertEqual({choice["value"] for choice in options["overlayLayout"]["choices"]},
                         {"row", "column"})
        self.assertIn("MaterialShapeWrappedMaterialSymbol", widget)
        self.assertIn('text: DiscordVoice.deafened ? "headset_off" : "headphones"', widget)
        self.assertIn("DiscordVoice.setDeafened(!DiscordVoice.deafened)", widget)
        self.assertIn("top: parent.top", widget)
        self.assertNotIn("anchors.fill: parent", widget)
        self.assertEqual(widget.count("implicitWidth: 48"), 2)
        self.assertEqual(widget.count("implicitSize: 46"), 2)
        self.assertIn("spacing: 0", widget)
        self.assertLess(widget.index("DiscordVoice.setMuted(!DiscordVoice.muted)"), widget.index("GridLayout"))
        self.assertIn("Math.min(channelName.implicitWidth", widget)
        self.assertIn("Item { Layout.fillWidth: true }", widget)
        self.assertIn('readonly property bool columnMode: layoutMode === "column"', widget)
        self.assertEqual(options["overlayAvatarSize"]["from"], 32)
        self.assertEqual(options["overlayAvatarSize"]["to"], 80)
        self.assertEqual({choice["value"] for choice in options["participantBackground"]["choices"]},
                         {"none", "card", "name"})
        self.assertEqual(options["participantBackgroundOpacity"]["from"], 0)
        self.assertEqual(options["participantBackgroundOpacity"]["to"], 1)
        self.assertEqual(options["participantBackgroundOpacity"]["step"], 0.05)
        self.assertIn('PluginState.option("discord_voice", "participantBackgroundOpacity"', widget)
        avatar = (PLUGIN / "ParticipantAvatar.qml").read_text()
        self.assertIn("property real backgroundOpacity", avatar)
        self.assertEqual(avatar.count("1 - root.backgroundOpacity"), 2)
        self.assertNotIn("anchors.fill: parent\n        visible: root.backgroundMode === \"card\"", avatar)
        self.assertIn("Math.min(ring.x, nameText.x)", avatar)
        self.assertIn("Math.max(ring.x + ring.width, nameText.x + nameText.width)", avatar)
        self.assertIn("Math.min(root.maxNameWidth, implicitWidth)", avatar)
        self.assertIn("nameText.width + Appearance.spacing.space200", avatar)
        self.assertIn('visible: root.showName && root.backgroundMode === "name"', avatar)
        self.assertIn("root.maxNameWidth", avatar)
        self.assertIn("root.backgroundMode === \"name\" ? Appearance.spacing.space200 : 0", avatar)
        self.assertIn("columnSpacing: root.columnMode ? Appearance.spacing.space75 : Appearance.spacing.space200", widget)
        self.assertIn("Config.options.plugins.blurOpacity", widget)
        self.assertIn("ColorUtils.transparentize", widget)
        self.assertIn(': "transparent"', widget)
        overlay = (ROOT / "modules/ii/overlay/discordVoice/DiscordVoiceOverlay.qml").read_text()
        self.assertIn("editorBackgroundOpacity: 0", overlay)
        # The resize boundary is the shared frame's default behaviour, gated on
        # overlayOpen. Re-asserting it here would only restate the default.
        self.assertNotIn("editorBorderVisible", overlay)
        frame = (ROOT / "modules/ii/overlay/StyledOverlayWidget.qml").read_text()
        self.assertIn("property bool editorBorderVisible: true", frame)
        self.assertIn("DiscordPackage.DiscordGlyph", overlay)
        fallback_bar = (PLUGIN / "BarWidget.qml").read_text()
        self.assertIn("DiscordGlyph", fallback_bar)
        self.assertNotIn('text: "voice_chat"', fallback_bar)
        native_bar = (ROOT / "modules/ii/bar/DiscordVoicePlugin.qml").read_text()
        self.assertIn("DiscordPackage.DiscordGlyph", native_bar)
        self.assertNotIn('text: "voice_chat"', native_bar)
        self.assertIn("border.width: 0", widget)

    def test_overlay_taskbar_renders_brand_icons_without_naming_the_plugin(self):
        taskbar = (ROOT / "modules/ii/overlay/OverlayTaskbar.qml").read_text()
        context = (ROOT / "modules/ii/overlay/OverlayContext.qml").read_text()
        # Shared overlay chrome must not special-case an individual widget, or
        # every future branded plugin needs another branch here.
        self.assertNotIn("discordVoice", taskbar)
        self.assertNotIn("DiscordPackage", taskbar)
        self.assertIn("property Component iconComponent: null", taskbar)
        self.assertIn("sourceComponent: widgetButton.iconComponent", taskbar)
        self.assertIn('property: "toggled"', taskbar)
        # The registry entry is what carries the branding.
        self.assertIn("iconComponent: root.discordVoiceIcon", context)
        self.assertIn("DiscordPackage.TaskbarGlyph", context)
        glyph = (PLUGIN / "TaskbarGlyph.qml").read_text()
        self.assertIn("property bool toggled", glyph)

    def test_overlay_width_grows_and_wraps_instead_of_clipping_avatars(self):
        widget = (PLUGIN / "Widget.qml").read_text()
        manifest = json.loads((PLUGIN / "manifest.json").read_text())
        options = {option["key"]: option for option in manifest["options"]}
        # Both inputs to the grid's width are user-configurable, so a fixed
        # implicitWidth would clip at the top of their ranges.
        largest_row = options["maxOverlayAvatars"]["to"] * options["overlayAvatarSize"]["to"]
        self.assertGreater(largest_row, 720)
        self.assertNotIn("implicitWidth: columnMode ? 256 : 344", widget)
        self.assertIn("readonly property real maxContentWidth: 720", widget)
        self.assertIn("columns: root.participantColumns", widget)
        self.assertIn("participantGridWidth + Appearance.spacing.space150 * 2", widget)
        # Derived arithmetically: reading the grid's implicitWidth back into
        # this item's implicitWidth would bind its width to itself.
        self.assertNotIn("implicitWidth: content.implicitWidth", widget)

    def test_participant_shape_memory_is_bounded(self):
        state = (PLUGIN / "ParticipantVisualState.js").read_text()
        self.assertIn("MAX_ENTRIES", state)
        self.assertIn("delete shapes[keys[index]]", state)
        # Re-inserting on touch keeps an active speaker from being evicted
        # ahead of someone who already left the call.
        self.assertIn("delete shapes[userId]", state)

    def test_numeric_plugin_options_reserve_label_space_without_slider_overlap(self):
        options = (ROOT / "modules/common/plugins/PluginOptions.qml").read_text()
        slider = (ROOT / "modules/common/widgets/ConfigSlider.qml").read_text()
        self.assertIn("textWidth: optionLoader.optionData.labelWidth ?? 176", options)
        # Elision, not a width floor, is what keeps the label off the slider.
        # A minimum would apply to every ConfigSlider in the settings window
        # and push narrow rows wider than their container.
        self.assertNotIn("Layout.minimumWidth: root.textWidth", slider)
        self.assertIn("Layout.preferredWidth: root.textWidth", slider)
        self.assertIn("Layout.maximumWidth: root.textWidth", slider)
        self.assertIn("Layout.minimumWidth: 96", slider)
        self.assertIn("elide: Text.ElideRight", slider)

    def test_bar_popup_uses_fixed_participant_cells_and_expressive_actions(self):
        popup = (PLUGIN / "DiscordVoicePopup.qml").read_text()
        self.assertIn("maxNameWidth: 64", popup)
        self.assertIn("contentPadding: Appearance.spacing.space200", popup)
        self.assertIn("implicitWidth: 384", popup)
        self.assertIn("MaterialShape.Shape.SoftBurst", popup)
        self.assertIn("MaterialShape.Shape.Clover4Leaf", popup)
        self.assertNotIn("toggled: DiscordVoice.muted", popup)
        self.assertNotIn("toggled: DiscordVoice.deafened", popup)
        self.assertIn('StyledToolTip { text: DiscordVoice.muted ? "Unmute" : "Mute" }', popup)
        self.assertNotIn('text: DiscordVoice.muted ? "Unmute" : "Mute"\n                        color:', popup)
        avatar = (PLUGIN / "ParticipantAvatar.qml").read_text()
        self.assertIn("property real maxNameWidth", avatar)
        self.assertIn('property string backgroundMode: "none"', avatar)

    def test_discord_brand_and_participant_state_shapes_are_expressive(self):
        glyph = (PLUGIN / "DiscordGlyph.qml").read_text()
        avatar = (PLUGIN / "ParticipantAvatar.qml").read_text()
        widget = (PLUGIN / "Widget.qml").read_text()
        self.assertIn('source: "discord.svg"', glyph)
        self.assertIn('iconFolder: Qt.resolvedUrl("assets")', glyph)
        self.assertTrue((PLUGIN / "assets" / "discord.svg").is_file())
        self.assertIn("MaterialShape.Shape.SoftBurst", avatar)
        self.assertIn("MaterialShape.Shape.Cookie4Sided", avatar)
        self.assertIn("MaterialShape.Shape.Boom", avatar)
        self.assertIn("shape: root.displayedShape", avatar)
        self.assertIn("onAvatarShapeChanged", avatar)
        self.assertIn('property: "transitionScale"', avatar)
        self.assertIn("ParticipantVisualState.previous", avatar)
        self.assertIn("shape: root.displayedShape", avatar)
        self.assertTrue((PLUGIN / "ParticipantVisualState.js").exists())
        self.assertIn("horizontalLayout: root.columnMode", widget)
        overlay = (ROOT / "modules/ii/overlay/discordVoice/DiscordVoiceOverlay.qml").read_text()
        self.assertIn("root.x + root.width / 2 >= root.parent.width / 2", overlay)

    def test_participants_update_in_place_without_reordering_or_delegate_flicker(self):
        service = SERVICE.read_text()
        widget = (PLUGIN / "Widget.qml").read_text()
        popup = (PLUGIN / "DiscordVoicePopup.qml").read_text()
        bar = (ROOT / "modules/ii/bar/DiscordVoicePlugin.qml").read_text()
        self.assertIn("id: participantsModel", service)
        self.assertIn("participantsModel.setProperty(existingIndex", service)
        self.assertIn("participantsModel.append({ participant: user })", service)
        self.assertIn("for (let index = participantsModel.count - 1", service)
        for consumer in (widget, popup, bar):
            self.assertIn("DiscordVoice.participantModel", consumer)


if __name__ == "__main__":
    unittest.main()
