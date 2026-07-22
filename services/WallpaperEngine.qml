import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

// Wallpaper Engine SELECTOR + selection state only.
//
// The old external-process renderer (linux-wallpaperengine --screen-root),
// cached stills, cross-fade transitions and in-shell blur backdrops have been
// removed - they are being replaced by a wallpaper surface that owns the WE
// frames directly (see project_embed_wallpaperengine). What remains here is:
//   - scanning the WE library (feeds the selector grid), and
//   - recording the picked project into config (activeProject/Path/Preview) so
//     the future embedded renderer and the selector's "active" indicator have
//     a source of truth, plus generating the palette from the preview.
// No wallpaper is rendered from this file anymore.
Singleton {
    id: root

    property var projects: []
    property bool loading: false
    property string error: ""
    readonly property bool available: projects.length > 0

    // Preview image of the active project, or the static wallpaper when none is
    // active. Consumed by the desktop menu / settings thumbnails.
    readonly property string activeArtwork: {
        const we = Config.options.wallpaperSelector.wallpaperEngine;
        return we.activePreview || Config.options.background.wallpaperPath;
    }

    readonly property string scannerPath: `${Directories.scriptPath}/wallpapers/wallpaper_engine.py`

    // --- Inert compatibility stubs -------------------------------------------
    // Kept only so existing consumers keep loading while the old WE rendering
    // path is torn out of them file by file. Remove once no consumer references
    // them. None of these do anything now (no live surface, stills, or blur).
    readonly property bool stableConfigured: false
    readonly property bool stillGenerating: false
    signal transitionRequested(string fromStill, string fromPreview, string toStill, string toPreview)
    function requestTransition(fromStill, fromPreview, toStill, toPreview) {}
    function recacheActiveStill() {}
    // -------------------------------------------------------------------------

    signal refreshed()

    function load() {
        if (!Config.ready || scanProcess.running) return;
        refresh();
    }

    function refresh() {
        root.loading = true;
        root.error = "";
        scanProcess.command = ["python3", root.scannerPath, "--root", Config.options.wallpaperSelector.wallpaperEngine.libraryPath];
        scanProcess.running = true;
    }

    // Shared dispatcher for mixed wallpaper models (selector + desktop menu).
    function selectEntry(entry, darkMode = Appearance.m3colors.darkmode) {
        if (!entry) return;
        if (entry.kind === "wallpaperEngine") {
            root.apply(entry.project, darkMode);
            return;
        }
        if (!entry.path) return;
        Wallpapers.select(entry.path, darkMode);
    }

    // Record the picked Wallpaper Engine project and refresh the palette from
    // its preview. Rendering the live wallpaper is the (future) embedded
    // surface's job, driven off this config.
    function apply(project, darkMode = Appearance.m3colors.darkmode) {
        if (!project || !project.path) return;
        Config.options.wallpaperSelector.wallpaperEngine.activeProject = project.id;
        Config.options.wallpaperSelector.wallpaperEngine.activePath = project.path;
        Config.options.wallpaperSelector.wallpaperEngine.activePreview = project.preview ?? "";
        if (project.preview) root.enqueueTheme(project, darkMode);
    }

    function enqueueTheme(project, darkMode = Appearance.m3colors.darkmode) {
        if (themeProcess.running) {
            themeProcess.pendingProject = project;
            return;
        }
        themeProcess.command = [
            Directories.wallpaperSwitchScriptPath,
            "--mode", darkMode ? "dark" : "light",
            "--coloronly", "--image", project.preview
        ];
        themeProcess.running = true;
    }

    // Clear the active Wallpaper Engine selection (selector "remove" action).
    function stop() {
        Config.options.wallpaperSelector.wallpaperEngine.activeProject = "";
        Config.options.wallpaperSelector.wallpaperEngine.activePath = "";
        Config.options.wallpaperSelector.wallpaperEngine.activePreview = "";
    }

    Process {
        id: themeProcess
        property var pendingProject: null
        onExited: exitCode => {
            const pending = themeProcess.pendingProject;
            themeProcess.pendingProject = null;
            if (exitCode !== 0)
                root.error = "Wallpaper theme generation failed";
            if (pending) Qt.callLater(() => root.enqueueTheme(pending));
        }
    }

    Process {
        id: scanProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.projects = Array.isArray(parsed) ? parsed : [];
                } catch (e) {
                    root.projects = [];
                    root.error = `Could not read Wallpaper Engine projects: ${e}`;
                }
            }
        }
        onExited: exitCode => {
            root.loading = false;
            if (exitCode !== 0)
                root.error = "Wallpaper Engine library scan failed";
            root.refreshed();
        }
    }
}
