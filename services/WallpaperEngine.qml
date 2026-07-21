import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    property var projects: []
    property bool loading: false
    property string error: ""
    readonly property bool stillGenerating: stillProcess.running
    readonly property bool available: projects.length > 0
    readonly property string scannerPath: `${Directories.scriptPath}/wallpapers/wallpaper_engine.py`
    readonly property string runnerPath: `${Directories.scriptPath}/wallpapers/wallpaper-engine.sh`
    readonly property string stillDir: `${FileUtils.trimFileProtocol(Directories.cache)}/wallpaperEngine`

    signal refreshed()
    signal applied(string projectId)
    signal transitionRequested(string fromStill, string fromPreview, string toStill, string toPreview)

    function stillPathFor(projectId) {
        return projectId ? `${root.stillDir}/${projectId}.png` : "";
    }

    function load() {
        if (!Config.ready || scanProcess.running) return;
        // Backfill the still for a wallpaper that was already active at startup.
        const we = Config.options.wallpaperSelector.wallpaperEngine;
        if (we.activeProject && we.activePath && !we.activeStill)
            root.ensureStill(we.activeProject, we.activePath);
        refresh();
    }

    function refresh() {
        root.loading = true;
        root.error = "";
        scanProcess.command = ["python3", root.scannerPath, "--root", Config.options.wallpaperSelector.wallpaperEngine.libraryPath];
        scanProcess.running = true;
    }

    function apply(project) {
        if (!project || !project.path) return;
        project.previousProject = Config.options.wallpaperSelector.wallpaperEngine.activeProject;
        project.previousPreview = Config.options.wallpaperSelector.wallpaperEngine.activePreview !== ""
            ? Config.options.wallpaperSelector.wallpaperEngine.activePreview
            : Config.options.background.wallpaperPath;
        Config.options.wallpaperSelector.wallpaperEngine.activeProject = project.id;
        Config.options.wallpaperSelector.wallpaperEngine.activePath = project.path;
        Config.options.wallpaperSelector.wallpaperEngine.activePreview = project.preview;
        root.ensureStill(project.id, project.path);
        if (project.preview) {
            themeProcess.project = project;
            themeProcess.command = [
                Directories.wallpaperSwitchScriptPath,
                "--mode", Appearance.m3colors.darkmode ? "dark" : "light",
                "--coloronly", "--image", project.preview
            ];
            themeProcess.running = true;
        } else {
            root.startRuntime(project);
        }
    }

    function startRuntime(project) {
        if (project.previousPreview && project.preview) {
            // Prefer full-scene stills; the background falls back to the previews
            // for any wallpaper whose still is not cached yet.
            const fromStill = project.previousProject ? root.stillPathFor(project.previousProject) : "";
            root.transitionRequested(fromStill, project.previousPreview,
                root.stillPathFor(project.id), project.preview);
        }
        Quickshell.execDetached([
            root.runnerPath, "apply", project.path,
            String(Config.options.wallpaperSelector.wallpaperEngine.fps),
            Config.options.wallpaperSelector.wallpaperEngine.scaling,
            Config.options.wallpaperSelector.wallpaperEngine.silent ? "true" : "false"
        ]);
        root.applied(project.id);
    }

    // Render (or reuse the cached) full-scene still for a project, then publish
    // it so the background can peel it as an opaque, parallax-able texture.
    function ensureStill(projectId, projectPath, force) {
        const out = root.stillPathFor(projectId);
        if (!out || !projectPath) return;
        stillProcess.projectId = projectId;
        stillProcess.outPath = out;
        stillProcess.command = [root.runnerPath, "screenshot", projectPath, out,
            Config.options.wallpaperSelector.wallpaperEngine.scaling, force ? "force" : ""];
        stillProcess.running = true;
    }

    // Re-render the active wallpaper's still, e.g. after its scene or the chosen
    // scaling changed. Forces past the cache.
    function recacheActiveStill() {
        const we = Config.options.wallpaperSelector.wallpaperEngine;
        if (!we.activeProject || !we.activePath || stillProcess.running) return;
        root.ensureStill(we.activeProject, we.activePath, true);
    }

    function stop() {
        Quickshell.execDetached([root.runnerPath, "stop"]);
        Config.options.wallpaperSelector.wallpaperEngine.activeProject = "";
        Config.options.wallpaperSelector.wallpaperEngine.activePath = "";
        Config.options.wallpaperSelector.wallpaperEngine.activePreview = "";
        Config.options.wallpaperSelector.wallpaperEngine.activeStill = "";
    }

    Process {
        id: stillProcess
        property string projectId: ""
        property string outPath: ""
        onExited: exitCode => {
            if (exitCode !== 0 || !stillProcess.outPath) return;
            // Ignore a stale render if the user has since switched wallpapers.
            if (stillProcess.projectId !== Config.options.wallpaperSelector.wallpaperEngine.activeProject) return;
            // Re-set (clear first) so an unchanged path still forces dependent
            // Images to reload now that the file exists.
            Config.options.wallpaperSelector.wallpaperEngine.activeStill = "";
            Config.options.wallpaperSelector.wallpaperEngine.activeStill = stillProcess.outPath;
        }
    }

    Process {
        id: themeProcess
        property var project: null
        onExited: exitCode => {
            if (exitCode !== 0)
                root.error = "Wallpaper theme generation failed";
            if (themeProcess.project)
                root.startRuntime(themeProcess.project);
            themeProcess.project = null;
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
