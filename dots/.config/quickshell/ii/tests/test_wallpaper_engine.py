#!/usr/bin/env python3
import importlib.util
import json
import os
import tempfile
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


class WallpaperEngineScannerTests(unittest.TestCase):
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


class WallpaperEngineSelectorTests(unittest.TestCase):
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

    def test_selector_reopens_on_the_active_wallpaper_source(self):
        selector = (ROOT / "modules/ii/wallpaperSelector/WallpaperSelectorContent.qml").read_text()
        self.assertIn(
            'property string source: Config.options.wallpaperSelector.wallpaperEngine.activeProject !== ""',
            selector,
        )
        self.assertIn('currentIndex: root.source === "wallpaperEngine" ? 1', selector)
        self.assertIn("onActivated: index =>", selector)
        self.assertGreaterEqual(selector.count("loadWorkshopOnce()"), 3)

    def test_selector_exposes_engine_source_and_clears_selection(self):
        selector = (ROOT / "modules/ii/wallpaperSelector/WallpaperSelectorContent.qml").read_text()
        self.assertIn('value: "wallpaperEngine"', selector)
        self.assertIn("WallpaperEngineGrid", selector)
        self.assertIn("WallpaperEngine.refresh()", selector)
        # stop() now just clears the recorded selection - no live runtime to kill.
        self.assertIn("WallpaperEngine.stop()", selector)
        # The image grid routes picks through selectEntry so the same dispatcher
        # records/clears the Wallpaper Engine selection.
        self.assertIn('WallpaperEngine.selectEntry({ kind: "wallpaperEngine", project: project }', selector)


class WallpaperEngineSelectionServiceTests(unittest.TestCase):
    def test_service_scans_and_records_without_rendering(self):
        service = (ROOT / "services/WallpaperEngine.qml").read_text()

        # Library scan feeds the selector grid.
        self.assertIn("function refresh()", service)
        self.assertIn('"python3", root.scannerPath, "--root"', service)
        self.assertIn("id: scanProcess", service)
        # selectEntry records the pick; it never starts a renderer/still/transition.
        self.assertIn("function selectEntry(entry, darkMode", service)
        self.assertIn('if (entry.kind === "wallpaperEngine")', service)
        self.assertIn("root.apply(entry.project, darkMode)", service)
        self.assertIn("Wallpapers.select(entry.path, darkMode)", service)
        self.assertIn("Config.options.wallpaperSelector.wallpaperEngine.activeProject = project.id", service)
        self.assertIn("function enqueueTheme(project", service)
        # The removed runtime/still/transition surface must not come back.
        self.assertNotIn("startRuntime", service)
        self.assertNotIn("requestTransition", service)
        self.assertNotIn("ensureStill", service)
        self.assertNotIn("stableConfigured", service)
        self.assertNotIn("Quickshell.execDetached", service)

    def test_desktop_menu_carousel_binds_structured_wallpaper_entries(self):
        menu = (ROOT / "modules/ii/desktopMenu/DesktopMenu.qml").read_text()

        self.assertIn('kind: "static", artwork: fp, path: fp', menu)
        self.assertIn('kind: "wallpaperEngine"', menu)
        self.assertIn("readonly property var entry: parent?.modelData ?? null", menu)
        self.assertIn("FileUtils.trimFileProtocol(entry.artwork)", menu)
        self.assertIn("WallpaperEngine.selectEntry(entry, Appearance.m3colors.darkmode)", menu)

    def test_settings_show_wallpaper_engine_artwork(self):
        service = (ROOT / "services/WallpaperEngine.qml").read_text()
        quick = (ROOT / "modules/ii/settings/pages/QuickConfig.qml").read_text()
        background = (ROOT / "modules/ii/settings/pages/BackgroundConfig.qml").read_text()

        self.assertIn("readonly property string activeArtwork:", service)
        self.assertIn("we.activePreview || Config.options.background.wallpaperPath", service)
        # Since the upstream "vb" merge the preview routes activeArtwork through
        # a video->thumbnail fallback (a raw video path can't render in an
        # Image), so assert the WE-artwork source plus the fallback rather than
        # the old bare binding.
        self.assertIn("? Config.options.background.thumbnailPath", quick)
        self.assertIn(": WallpaperEngine.activeArtwork", quick)
        self.assertGreaterEqual(background.count("WallpaperEngine.activeArtwork"), 2)

    def test_quick_palette_changes_reuse_active_artwork(self):
        quick_config = (ROOT / "modules/ii/settings/pages/QuickConfig.qml").read_text()

        self.assertIn('const artwork = WallpaperEngine.activeArtwork', quick_config)
        self.assertIn('"--noswitch", "--coloronly"', quick_config)


class WallpaperScriptTests(unittest.TestCase):
    def test_color_only_theming_does_not_stop_live_wallpapers(self):
        switcher = (ROOT / "scripts/colors/switchwall.sh").read_text()
        self.assertIn('[[ -z "$coloronly" ]] && kill_existing_mpvpaper', switcher)
        self.assertIn('[[ -z "$coloronly" ]] && check_and_prompt_upscale "$imgpath" &', switcher)

    def test_presets_theme_from_engine_preview_without_a_runtime(self):
        presets = (ROOT / "scripts/presets.sh").read_text()
        self.assertIn(".wallpaperSelector.wallpaperEngine.activePath // empty", presets)
        self.assertIn('"$SWITCHWALL" --noswitch --coloronly --image "$engine_preview"', presets)
        # No external Wallpaper Engine runner anymore.
        self.assertNotIn("WALLPAPER_ENGINE", presets)
        self.assertNotIn("wallpaper-engine.sh", presets)


if __name__ == "__main__":
    unittest.main()
