#!/usr/bin/env python3
import importlib.util
import json
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCANNER = ROOT / "scripts/wallpapers/wallpaper_engine.py"


def load_scanner():
    spec = importlib.util.spec_from_file_location("wallpaper_engine_scanner", SCANNER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


class WallpaperEngineTests(unittest.TestCase):
    def test_config_reload_cannot_flip_plugins_to_static_blur(self):
        service = (ROOT / "services/WallpaperEngine.qml").read_text()
        plugin = (ROOT / "modules/common/plugins/PluginWidget.qml").read_text()
        background = (ROOT / "modules/ii/background/Background.qml").read_text()
        user_card = (ROOT / "modules/ii/background/widgets/usercard/UserCardWidget.qml").read_text()

        self.assertIn("property bool stableConfigured: false", service)
        self.assertIn("id: configuredOffTimer", service)
        self.assertIn("onConfiguredProjectChanged: root.syncConfiguredState()", service)
        self.assertIn("WallpaperEngine.stableConfigured", plugin)
        self.assertIn("WallpaperEngine.stableConfigured", background)
        self.assertIn("WallpaperEngine.stableConfigured", user_card)

    def test_plugins_use_live_compositor_blur_without_loader_transform(self):
        plugin = (ROOT / "modules/common/plugins/PluginWidget.qml").read_text()
        background = (ROOT / "modules/ii/background/Background.qml").read_text()
        carrier = (ROOT / "modules/common/widgets/LiveWallpaperBlur.qml").read_text()
        surface = (ROOT / "modules/common/widgets/WallpaperBlurSurface.qml").read_text()

        self.assertIn("model: rootWidget.blurEnabled", plugin)
        self.assertIn("opacity: 0.1", carrier)
        self.assertIn("layer.effect: OpacityMask", surface)
        self.assertIn("FastBlur {", surface)
        self.assertNotIn("sharedWallpaperBlurSource", plugin)
        plugin_loader = background.split("id: pluginLoader", 1)[1].split(
            "sourceComponent: PluginWidget", 1
        )[0]
        self.assertNotIn("transform: Scale", plugin_loader)

    def test_live_wallpaper_does_not_run_hidden_static_transition(self):
        background = (ROOT / "modules/ii/background/Background.qml").read_text()
        handler = background.split("onWallpaperPathChanged:", 1)[1].split(
            "onWallpaperEngineConfiguredChanged:", 1
        )[0]

        self.assertIn("if (bgRoot.wallpaperEngineConfigured)", handler)
        self.assertIn('previousWallpaper.source = ""', handler)
        self.assertIn('wallpaper.source = ""', handler)
        self.assertIn("transitionAnim.stop()", handler)

    def test_live_transition_prefers_cached_still_with_preview_fallback(self):
        background = (ROOT / "modules/ii/background/Background.qml").read_text()
        transition = background.split("function startEngineTransition", 1)[1].split(
            "screen: modelData", 1
        )[0]

        # Match the lock: peel monitor-shaped stills on both sides, falling back
        # to the (often square) preview only when a still is not cached, so the
        # incoming wallpaper is never stretched.
        self.assertIn("const fromSrc = fromStill || fromPreview", transition)
        self.assertIn("const toSrc = toStill || toPreview", transition)
        self.assertIn("engineSwitchTransition.setSources(fromSrc, fromPreview, toSrc, toPreview)", transition)

    def test_live_transition_preloads_previews_before_runtime_swap(self):
        background = (ROOT / "modules/ii/background/Background.qml").read_text()
        component = (ROOT / "modules/ii/background/widgets/WallpaperEngineTransition.qml").read_text()
        transition_layer = background.split("id: engineTransitionLayer", 1)[1].split(
            "id: previousWallpaper", 1
        )[0]

        # The switch decodes synchronously (preload) because the runtime is
        # swapped right after the request returns; the component wires that to
        # both source Images' asynchronous flag.
        self.assertIn("preload: true", transition_layer)
        self.assertEqual(component.count("asynchronous: !transition.preload"), 2)

    def test_wallpaper_engine_search_toolbar_is_visible_on_entry(self):
        selector = (ROOT / "modules/ii/wallpaperSelector/WallpaperSelectorContent.qml").read_text()

        self.assertIn('if (source === "wallpaperEngine")', selector)
        self.assertGreaterEqual(selector.count("showControls = true"), 2)
        self.assertIn("Component.onCompleted:", selector)

    def test_wallpaper_engine_workshop_refreshes_once_per_selector_open(self):
        selector = (ROOT / "modules/ii/wallpaperSelector/WallpaperSelectorContent.qml").read_text()

        self.assertIn("property bool workshopLoadedThisOpen: false", selector)
        self.assertIn("function loadWorkshopOnce()", selector)
        self.assertIn("if (source !== \"wallpaperEngine\" || workshopLoadedThisOpen)", selector)
        self.assertEqual(selector.count("WallpaperEngine.refresh()"), 2)  # guarded load + manual button

    def test_fullscreen_transition_layers_are_allocated_only_while_visible(self):
        background = (ROOT / "modules/ii/background/Background.qml").read_text()

        # The transition layer only draws while the transition is active, and the
        # lock overlay only while it is on screen, so nothing renders otherwise.
        transition_layer = background.split("id: engineTransitionLayer", 1)[1].split(
            "id: previousWallpaper", 1
        )[0]
        self.assertIn("visible: bgRoot.engineTransitionActive", transition_layer)
        self.assertIn("visible: bgRoot.wallpaperEngineConfigured && bgRoot.wallpaperEngineLockProgress > 0", background)
        self.assertIn("source: wallpaperEngineLockOverlay.visible", background)
        self.assertIn("&& bgRoot.transitionProgress < 1", background)

    def test_desktop_menu_carousel_binds_structured_wallpaper_entries(self):
        menu = (ROOT / "modules/ii/desktopMenu/DesktopMenu.qml").read_text()

        self.assertIn('kind: "static", artwork: fp, path: fp', menu)
        self.assertIn('kind: "wallpaperEngine"', menu)
        self.assertIn("readonly property var entry: parent?.modelData ?? null", menu)
        self.assertIn("FileUtils.trimFileProtocol(entry.artwork)", menu)
        self.assertIn("WallpaperEngine.selectEntry(entry, Appearance.m3colors.darkmode)", menu)

        service = (ROOT / "services/WallpaperEngine.qml").read_text()
        selector = (ROOT / "modules/ii/wallpaperSelector/WallpaperSelectorContent.qml").read_text()
        self.assertIn("function selectEntry(entry, darkMode", service)
        self.assertIn('if (entry.kind === "wallpaperEngine")', service)
        self.assertIn("root.apply(entry.project)", service)
        self.assertIn("root.requestTransition(fromStill, fromPreview, entry.path, entry.path)", service)
        self.assertIn("Wallpapers.select(entry.path, darkMode)", service)
        self.assertIn('WallpaperEngine.selectEntry({ kind: "wallpaperEngine", project: project }', selector)

    def test_quick_palette_changes_preserve_the_live_wallpaper(self):
        quick_config = (ROOT / "modules/ii/settings/pages/QuickConfig.qml").read_text()

        self.assertIn('const artwork = WallpaperEngine.activeArtwork', quick_config)
        self.assertIn('"--noswitch", "--coloronly"', quick_config)
        self.assertIn('page.refreshTheme(["--mode"', quick_config)
        self.assertIn('page.refreshTheme(["--type", modelData.value])', quick_config)
        self.assertIn('page.refreshTheme(["--color"])', quick_config)
        self.assertNotIn('execDetached(["bash", "-c"', quick_config)

    def test_scanner_reads_metadata_and_skips_malformed_projects(self):
        scanner = load_scanner()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            valid = root / "123"
            valid.mkdir()
            (valid / "preview.jpg").write_bytes(b"preview")
            (valid / "project.json").write_text(json.dumps({
                "title": "A live wallpaper",
                "type": "scene",
                "preview": "preview.jpg",
                "tags": ["Relaxing"],
            }))
            invalid = root / "456"
            invalid.mkdir()
            (invalid / "project.json").write_text("not json")

            projects = scanner.scan(str(root))

            self.assertEqual(len(projects), 1)
            self.assertEqual(projects[0]["id"], "123")
            self.assertEqual(projects[0]["title"], "A live wallpaper")
            self.assertEqual(projects[0]["preview"], str(valid / "preview.jpg"))

    def test_scanner_confines_preview_to_the_project_directory(self):
        scanner = load_scanner()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            secret = root / "secret.jpg"
            secret.write_bytes(b"not for the picker")
            project = root / "789"
            project.mkdir()
            # An absolute path and a "../" escape must both be rejected: only a
            # preview inside the project directory is trusted.
            (project / "project.json").write_text(json.dumps({
                "title": "Escapes its directory",
                "preview": "../secret.jpg",
            }))

            projects = scanner.scan(str(root))

            self.assertEqual(len(projects), 1)
            self.assertEqual(projects[0]["preview"], "")

    def test_scanner_uses_a_confined_fallback_preview(self):
        scanner = load_scanner()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "790"
            project.mkdir()
            fallback = project / "preview.jpg"
            fallback.write_bytes(b"preview")
            (project / "project.json").write_text(json.dumps({
                "title": "Uses fallback",
                "preview": "../outside.jpg",
            }))

            projects = scanner.scan(str(root))

            self.assertEqual(projects[0]["preview"], str(fallback))

    def test_scanner_deduplicates_workshop_ids_across_libraries(self):
        scanner = load_scanner()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first_root = root / "first"
            second_root = root / "second"
            first = first_root / "123"
            second = second_root / "123"
            first.mkdir(parents=True)
            second.mkdir(parents=True)
            (first / "project.json").write_text(json.dumps({"title": "Older"}))
            (second / "project.json").write_text(json.dumps({"title": "Newer"}))
            os.utime(first / "project.json", ns=(1, 1))
            os.utime(second / "project.json", ns=(2, 2))
            original_roots = scanner.project_roots
            scanner.project_roots = lambda configured: [first_root, second_root]
            try:
                projects = scanner.scan("")
            finally:
                scanner.project_roots = original_roots

            self.assertEqual(len(projects), 1)
            self.assertEqual(projects[0]["title"], "Newer")

    def test_runner_checks_for_its_runtime_dependencies(self):
        runner = (ROOT / "scripts/wallpapers/wallpaper-engine.sh").read_text()
        self.assertIn("for tool in linux-wallpaperengine hyprctl jq", runner)

    def test_runner_uses_one_bounded_runtime_for_all_monitors(self):
        runner = (ROOT / "scripts/wallpapers/wallpaper-engine.sh").read_text()
        self.assertIn('mapfile -t monitors', runner)
        self.assertIn('args+=(--screen-root "$monitor" --scaling "$scaling")', runner)
        # Exactly one persistent multi-monitor runtime. The screenshot action
        # spawns its own throwaway instance, so count the bounded launch itself.
        self.assertEqual(runner.count('setsid linux-wallpaperengine "${args[@]}"'), 1)
        self.assertIn('pid_file="$state_dir/runtime.pid"', runner)
        self.assertIn('kill -- "-$pid"', runner)
        self.assertIn("pkill -f '(^|/)[l]inux-wallpaperengine .*--layer background( |$)'", runner)
        self.assertNotIn("pkill -f '(^|/)[l]inux-wallpaperengine( |$)'", runner)
        self.assertIn("grep -q -- '--layer'", runner)
        self.assertIn('args=(--layer background --fps "$fps")', runner)
        self.assertNotIn("\neval ", runner)

    def test_runtime_pauses_reactively_for_fullscreen_clients(self):
        runner = (ROOT / "scripts/wallpapers/wallpaper-engine.sh").read_text()
        service = (ROOT / "services/WallpaperEngine.qml").read_text()

        self.assertIn('if [[ "$action" == "pause" ]]', runner)
        self.assertIn('if [[ "$action" == "resume" ]]', runner)
        self.assertIn('kill -STOP -- "-$pid"', runner)
        self.assertIn('kill -CONT -- "-$pid"', runner)
        self.assertIn("if fullscreen_active; then", runner)
        self.assertIn("readonly property bool fullscreenActive:", service)
        self.assertIn("HyprlandData.workspaceById[monitor?.activeWorkspace?.id]?.hasfullscreen", service)
        self.assertIn("onFullscreenActiveChanged:", service)
        self.assertIn('paused ? "pause" : "resume"', service)

    def test_runner_builds_a_single_multi_monitor_command(self):
        runner = ROOT / "scripts/wallpapers/wallpaper-engine.sh"
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            bin_dir = temp / "bin"
            project = temp / "project"
            bin_dir.mkdir()
            project.mkdir()
            (bin_dir / "hyprctl").write_text("#!/bin/sh\nprintf '[{\"name\":\"DP-1\"},{\"name\":\"HDMI-A-1\"}]\\n'\n")
            (bin_dir / "jq").write_text("#!/bin/sh\nprintf 'DP-1\\nHDMI-A-1\\n'\n")
            (bin_dir / "pkill").write_text("#!/bin/sh\nexit 0\n")
            (bin_dir / "linux-wallpaperengine").write_text(
                "#!/bin/sh\n"
                "if [ \"${1:-}\" = --help ]; then printf '%s\\n' '--layer'; fi\n"
                "exit 0\n"
            )
            (bin_dir / "setsid").write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" > \"$TEST_COMMAND_FILE\"\n"
            )
            for executable in bin_dir.iterdir():
                executable.chmod(0o755)
            command_file = temp / "command"
            environment = os.environ | {
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "XDG_STATE_HOME": str(temp / "state"),
                "XDG_CONFIG_HOME": str(temp / "config"),
                "TEST_COMMAND_FILE": str(command_file),
            }
            subprocess.run(
                [str(runner), "apply", str(project), "60", "fit", "true"],
                check=True,
                env=environment,
            )
            for _ in range(50):
                if command_file.exists():
                    break
                time.sleep(0.01)
            self.assertTrue(command_file.exists(), "detached runtime command was not launched")
            command = command_file.read_text()
            self.assertEqual(command.count("--screen-root"), 2)
            self.assertIn("--fps 60", command)
            self.assertIn("--silent", command)
            self.assertIn(str(project), command)

    def test_selector_exposes_engine_source_and_managed_controls(self):
        selector = (ROOT / "modules/ii/wallpaperSelector/WallpaperSelectorContent.qml").read_text()
        service = (ROOT / "services/WallpaperEngine.qml").read_text()
        self.assertIn('value: "wallpaperEngine"', selector)
        self.assertIn("WallpaperEngineGrid", selector)
        self.assertIn("WallpaperEngine.refresh()", selector)
        self.assertIn("WallpaperEngine.stop()", selector)
        self.assertIn('"--coloronly", "--image", project.preview', service)
        self.assertIn("onExited: exitCode =>", service)
        self.assertIn("function enqueueTheme(project)", service)
        self.assertIn("property var pendingProject: null", service)
        self.assertIn("root.startRuntime(completedProject)", service)
        self.assertIn("signal transitionRequested(string fromStill, string fromPreview, string toStill, string toPreview)", service)
        self.assertIn("root.requestTransition(fromStill, project.previousPreview,", service)
        self.assertIn("Config.options.wallpaperSelector.wallpaperEngine.activeProject", service)

    def test_wallpaper_jobs_are_serialized_and_keep_latest_theme(self):
        service = (ROOT / "services/WallpaperEngine.qml").read_text()
        self.assertIn("property var stillQueue: []", service)
        self.assertIn("if (stillProcess.running)", service)
        self.assertIn("root.stillQueue = [job]", service)
        self.assertIn("function startNextStillJob()", service)
        self.assertIn("Qt.callLater(root.startNextStillJob)", service)
        self.assertIn("if (themeProcess.running)", service)
        self.assertIn("themeProcess.pendingProject = project", service)
        self.assertIn("completedProject.id === Config.options.wallpaperSelector.wallpaperEngine.activeProject", service)

    def test_selector_reopens_on_the_active_wallpaper_source(self):
        selector = (ROOT / "modules/ii/wallpaperSelector/WallpaperSelectorContent.qml").read_text()
        self.assertIn(
            'property string source: Config.options.wallpaperSelector.wallpaperEngine.activeProject !== ""',
            selector,
        )
        self.assertIn('currentIndex: root.source === "wallpaperEngine" ? 1', selector)
        self.assertIn("onActivated: index =>", selector)
        self.assertGreaterEqual(selector.count("loadWorkshopOnce()"), 3)
        self.assertNotIn("onCurrentIndexChanged: {\n                                root.source", selector)

    def test_color_only_theming_does_not_stop_live_wallpapers(self):
        switcher = (ROOT / "scripts/colors/switchwall.sh").read_text()
        self.assertIn('[[ -z "$coloronly" ]] && kill_existing_mpvpaper', switcher)
        self.assertIn('[[ -z "$coloronly" ]] && check_and_prompt_upscale "$imgpath" &', switcher)

    def test_static_wallpaper_is_hidden_while_engine_is_active(self):
        background = (ROOT / "modules/ii/background/Background.qml").read_text()
        self.assertIn("readonly property bool wallpaperEngineActive:", background)
        self.assertIn("visible: !bgRoot.wallpaperEngineConfigured", background)
        self.assertIn("running: Config.options.wallpaperSelector.changeInterval > 0 && !bgRoot.wallpaperEngineActive", background)
        self.assertIn("wallpaperPath: bgRoot.widgetWallpaperPath", background)

    def test_live_wallpaper_changes_use_configured_transition_shader(self):
        background = (ROOT / "modules/ii/background/Background.qml").read_text()
        self.assertIn("function onTransitionRequested(fromStill, fromPreview, toStill, toPreview)", background)
        self.assertIn("bgRoot.startEngineTransition(fromStill, fromPreview, toStill, toPreview)", background)
        # Stills are preferred on both sides with a preview fallback for uncached
        # wallpapers, so neither side is stretched.
        self.assertIn("const fromSrc = fromStill || fromPreview", background)
        self.assertIn("const toSrc = toStill || toPreview", background)
        self.assertIn("duration: Appearance.wallpaperTransitionDuration", background)
        # Both the lock and the switch route the configured shader through the
        # shared transition component.
        component = (ROOT / "modules/ii/background/widgets/WallpaperEngineTransition.qml").read_text()
        self.assertIn('Qt.resolvedUrl(`../shaders/${transition.shader}.frag.qsb`)', component)
        self.assertIn("shader: bgRoot.currentShader", background)

    def test_live_wallpaper_blur_matches_user_card_compositor_carrier(self):
        plugin = (ROOT / "modules/common/plugins/PluginWidget.qml").read_text()
        user_card = (ROOT / "modules/ii/background/widgets/usercard/UserCardWidget.qml").read_text()
        carrier = (ROOT / "modules/common/widgets/LiveWallpaperBlur.qml").read_text()
        surface = (ROOT / "modules/common/widgets/WallpaperBlurSurface.qml").read_text()
        self.assertIn("import qs.services", plugin)
        self.assertIn("readonly property bool liveWallpaperActive:", plugin)
        self.assertIn("WallpaperBlurSurface {", plugin)
        self.assertIn("model: rootWidget.blurEnabled", plugin)
        self.assertIn("z: 0", plugin)
        self.assertIn("z: 1", plugin)
        self.assertIn("readonly property bool liveWallpaperActive:", user_card)
        self.assertIn("visible: !root.liveWallpaperActive", surface)
        # The User Card and plugin widgets share the single WallpaperBlurSurface
        # instead of duplicating the image + FastBlur + carrier structure.
        self.assertIn("WallpaperBlurSurface {", user_card)
        self.assertNotIn("id: bgImage", user_card)
        # The still path samples the wallpaper region behind the surface (via its
        # absolute monitor position) rather than cropping the whole wallpaper into
        # the widget rect, matching the live compositor blur's framing.
        self.assertIn("surfaceX:", user_card)
        self.assertIn("surfaceX:", plugin)
        self.assertIn("sourceClipRect:", surface)
        self.assertIn("LiveWallpaperBlur {", surface)
        self.assertIn("Rectangle {", carrier)
        self.assertIn("opacity: 0.1", carrier)
        self.assertNotIn("layer.enabled", carrier)
        self.assertNotIn("ShaderEffect", carrier)

    def test_lock_transition_promotes_the_surface_immediately_and_peels_a_still(self):
        background = (ROOT / "modules/ii/background/Background.qml").read_text()
        self.assertIn("readonly property bool wallpaperEngineConfigured:", background)
        self.assertIn("id: wallpaperEngineLockOverlay", background)
        self.assertIn("property real wallpaperEngineLockProgress: 0", background)
        # Under WlSessionLock the background must reach the Overlay layer the
        # instant locking begins (and hold it until the reverse peel finishes),
        # or the animation plays hidden beneath the lock surface. A delayed timer
        # promotion is exactly the bug this replaced.
        self.assertIn(
            "(GlobalStates.screenLocked || bgRoot.wallpaperEngineLockProgress > 0) ? WlrLayer.Overlay",
            background,
        )
        self.assertNotIn("wallpaperEngineLockLayerPromoted", background)
        self.assertNotIn("wallpaperEngineLockLayerTimer", background)
        lock_handler = background.index("function onScreenLockedChanged()")
        shader_selection = background.index("bgRoot.currentShader =", lock_handler)
        progress = background.index(
            "bgRoot.wallpaperEngineLockProgress = GlobalStates.screenLocked ? 1 : 0", lock_handler
        )
        self.assertLess(shader_selection, progress)
        self.assertIn("duration: Appearance.wallpaperTransitionDuration", background)
        # The lock and the switch share one transition component. The lock's
        # from-side is the opaque full-scene still (so it covers the compositor-
        # blurred live surface and can be parallaxed), transitioning to the lock
        # wallpaper; the still falls back to the preview when uncached.
        component = (ROOT / "modules/ii/background/widgets/WallpaperEngineTransition.qml").read_text()
        lock_block = background[background.index("id: lockTransition"):background.index("id: wallpaperEngineLockImage")]
        self.assertIn(
            "? Config.options.wallpaperSelector.wallpaperEngine.activeStill",
            lock_block,
        )
        self.assertIn("fromFallback: Config.options.wallpaperSelector.wallpaperEngine.activePreview", lock_block)
        self.assertIn("progress: bgRoot.wallpaperEngineLockProgress", lock_block)
        self.assertIn("shader: bgRoot.currentShader", lock_block)
        # Both sides prefer the monitor-shaped still (preview only as a fallback),
        # so the shader samples correctly-framed textures and nothing stretches.
        self.assertIn("property var fromImage: fromView", component)
        self.assertIn("property var toImage: toView", component)
        self.assertEqual(component.count("fillMode: Image.PreserveAspectCrop"), 2)
        # Both call sites instantiate the same component.
        self.assertIn("WallpaperEngineTransition {", background)
        self.assertGreaterEqual(background.count("WallpaperEngineTransition {"), 2)

    def test_peel_parallax_is_clamped_so_edges_cannot_stretch(self):
        peel = (ROOT / "modules/ii/background/shaders/Peel.frag").read_text()
        self.assertIn("texture(fromImage, fromUv)", peel)
        self.assertIn("texture(toImage, toUv)", peel)
        # Parallax drifts both layers, but every offset UV is clamped to [0,1] so
        # a sample can never run off the texture and smear its edge across screen.
        self.assertIn("clamp(uv - axis", peel)
        self.assertIn("clamp(uv + axis", peel)
        self.assertNotIn("uv + axis * (t * amount)", peel.replace("clamp(uv + axis", ""))

    def test_active_still_is_generated_and_cached_for_transitions(self):
        runner = (ROOT / "scripts/wallpapers/wallpaper-engine.sh").read_text()
        service = (ROOT / "services/WallpaperEngine.qml").read_text()
        config = (ROOT / "modules/common/Config.qml").read_text()
        # Runner renders offscreen (no --screen-root/--window) and caches.
        self.assertIn('if [[ "$action" == "screenshot" ]]; then', runner)
        self.assertIn("--screenshot", runner)
        self.assertIn('[[ -s "$out" ]] && return 0', runner)
        # Capture at monitor resolution (windowed) so the still matches the live
        # framing rather than the small square a geometry-less render produces.
        gen = runner[runner.index("generate_screenshot"):runner.index('if [[ "$action" == "stop"')]
        self.assertIn('--window "$geo"', gen)
        self.assertIn('select(.focused)', gen)
        self.assertNotIn("--screen-root", gen)
        # Service publishes the cached still path; config carries it.
        self.assertIn("function ensureStill(", service)
        self.assertIn("activeStill", service)
        self.assertIn("property string activeStill:", config)

    def test_video_stills_are_scaled_and_cache_keys_include_framing(self):
        runner = (ROOT / "scripts/wallpapers/wallpaper-engine.sh").read_text()
        service = (ROOT / "services/WallpaperEngine.qml").read_text()

        self.assertIn('select(.type == "video") | .file // empty', runner)
        self.assertIn('force_original_aspect_ratio=increase,crop=', runner)
        self.assertIn('force_original_aspect_ratio=decrease,pad=', runner)
        self.assertIn('filter="scale=${monitor_width}:${monitor_height}"', runner)
        self.assertIn('ffmpeg -v error -y -ss 5', runner)
        self.assertIn('"$video_path" == "$resolved_dir/"*', runner)
        self.assertIn('${projectId}-${scaling}-v2.png', service)
        self.assertIn('Config.options.wallpaperSelector.wallpaperEngine.activeStill = ""', service)

    def test_wallpaper_engine_art_is_used_by_user_surfaces(self):
        background = (ROOT / "modules/ii/background/Background.qml").read_text()
        user_card = (ROOT / "modules/ii/background/widgets/usercard/UserCardWidget.qml").read_text()
        surface = (ROOT / "modules/common/widgets/WallpaperBlurSurface.qml").read_text()
        sidebar = (ROOT / "modules/ii/sidebarRight/SidebarRightContent.qml").read_text()
        self.assertIn("wallpaperPath: bgRoot.widgetWallpaperPath", background)
        self.assertIn("wallpaperSource: root.wallpaperPath", user_card)
        self.assertIn('source: root.wallpaperSource ? ("file://" + root.wallpaperSource) : ""', surface)
        self.assertIn("Config.options.wallpaperSelector.wallpaperEngine.activePreview", sidebar)
        self.assertNotIn("liveWallpaperBanner", sidebar)
        self.assertNotIn("CutoutFill", sidebar)

    def test_settings_and_presets_show_wallpaper_engine_artwork(self):
        service = (ROOT / "services/WallpaperEngine.qml").read_text()
        quick = (ROOT / "modules/ii/settings/pages/QuickConfig.qml").read_text()
        background = (ROOT / "modules/ii/settings/pages/BackgroundConfig.qml").read_text()
        profile = (ROOT / "modules/ii/settings/pages/Profile.qml").read_text()
        self.assertIn("readonly property string activeArtwork:", service)
        self.assertIn("return we.activeStill || we.activePreview", service)
        self.assertIn("source: WallpaperEngine.activeArtwork", quick)
        self.assertGreaterEqual(background.count("WallpaperEngine.activeArtwork"), 2)
        self.assertIn("engine.activeStill || engine.activePreview", profile)

    def test_presets_restore_the_saved_wallpaper_mode(self):
        presets = (ROOT / "scripts/presets.sh").read_text()
        self.assertIn('WALLPAPER_ENGINE=', presets)
        self.assertIn(".wallpaperSelector.wallpaperEngine.activePath // empty", presets)
        self.assertIn('"$WALLPAPER_ENGINE" apply "$engine_path"', presets)
        self.assertIn('"$WALLPAPER_ENGINE" stop', presets)



if __name__ == "__main__":
    unittest.main()
