import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    // JsonAdapter reloads can briefly expose nested string properties as their
    // defaults while replacing config.json. Do not let that transient empty
    // activeProject switch every desktop plugin from compositor blur to its
    // static-image blur path: each path decodes and renders wallpaper textures,
    // producing a multi-gigabyte allocation burst during preset changes.
    readonly property string configuredProject: Config.options.wallpaperSelector.wallpaperEngine.activeProject
    property bool stableConfigured: false
    property var projects: []
    property var stillQueue: []
    property bool loading: false
    property string error: ""
    readonly property bool stillGenerating: stillProcess.running
    readonly property bool available: projects.length > 0
    readonly property bool fullscreenActive: HyprlandData.monitors.some(monitor =>
        HyprlandData.workspaceById[monitor?.activeWorkspace?.id]?.hasfullscreen ?? false)
    readonly property string activeArtwork: {
        const we = Config.options.wallpaperSelector.wallpaperEngine;
        if (!we.activeProject) return Config.options.background.wallpaperPath;
        return we.activeStill || we.activePreview || Config.options.background.wallpaperPath;
    }
    readonly property string scannerPath: `${Directories.scriptPath}/wallpapers/wallpaper_engine.py`
    readonly property string runnerPath: `${Directories.scriptPath}/wallpapers/wallpaper-engine.sh`
    readonly property string stillDir: `${FileUtils.trimFileProtocol(Directories.cache)}/wallpaperEngine`

    signal refreshed()
    signal applied(string projectId)
    signal transitionRequested(string fromStill, string fromPreview, string toStill, string toPreview)

    function syncConfiguredState() {
        if (root.configuredProject !== "") {
            configuredOffTimer.stop();
            root.stableConfigured = true;
        } else {
            configuredOffTimer.restart();
        }
    }

    onConfiguredProjectChanged: root.syncConfiguredState()
    Component.onCompleted: root.syncConfiguredState()

    Timer {
        id: configuredOffTimer
        // Longer than Config's watched-file reload window, while short enough
        // to hand a real Wallpaper Engine -> static transition over promptly.
        interval: 500
        repeat: false
        onTriggered: root.stableConfigured = root.configuredProject !== ""
    }

    onFullscreenActiveChanged: {
        if (Config.options.wallpaperSelector.wallpaperEngine.activeProject)
            root.setPaused(fullscreenActive);
    }

    function setPaused(paused) {
        Quickshell.execDetached([root.runnerPath, paused ? "pause" : "resume"]);
    }

    function requestTransition(fromStill, fromPreview, toStill, toPreview) {
        root.transitionRequested(fromStill, fromPreview, toStill, toPreview);
    }

    // Shared dispatcher for mixed wallpaper models. UI surfaces should not
    // duplicate source detection or Wallpaper Engine transition setup.
    function selectEntry(entry, darkMode = Appearance.m3colors.darkmode) {
        if (!entry) return;
        if (entry.kind === "wallpaperEngine") {
            root.apply(entry.project);
            return;
        }
        if (!entry.path) return;

        const engine = Config.options.wallpaperSelector.wallpaperEngine;
        if (engine.activeProject) {
            const fromStill = engine.activeStill || root.stillPathFor(engine.activeProject);
            const fromPreview = engine.activePreview || Config.options.background.wallpaperPath;
            root.requestTransition(fromStill, fromPreview, entry.path, entry.path);
        }
        Wallpapers.select(entry.path, darkMode);
    }

    function stillPathFor(projectId) {
        const scaling = Config.options.wallpaperSelector.wallpaperEngine.scaling || "fill";
        return projectId ? `${root.stillDir}/${projectId}-${scaling}-v2.png` : "";
    }

    function load() {
        if (!Config.ready || scanProcess.running) return;
        // Backfill the still for a wallpaper that was already active at startup.
        const we = Config.options.wallpaperSelector.wallpaperEngine;
        if (we.activeProject && we.activePath) {
            const expectedStill = root.stillPathFor(we.activeProject);
            if (we.activeStill !== expectedStill) {
                Config.options.wallpaperSelector.wallpaperEngine.activeStill = "";
                root.ensureStill(we.activeProject, we.activePath);
            }
        }
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
        const prevProject = Config.options.wallpaperSelector.wallpaperEngine.activeProject;
        // Only trust activePreview when a project is actually active. Switching
        // away to a static image clears activeProject but leaves activePreview
        // holding the old project's preview, which would otherwise make an
        // image->engine transition peel from a stale previous wallpaper instead
        // of the image currently on screen.
        const prevPreview = prevProject !== ""
            ? (Config.options.wallpaperSelector.wallpaperEngine.activePreview !== ""
                ? Config.options.wallpaperSelector.wallpaperEngine.activePreview
                : Config.options.background.wallpaperPath)
            : Config.options.background.wallpaperPath;
        // Start the cross-fade before flipping any config. When switching from a
        // static image the outgoing wallpaper is a Quickshell layer that hides
        // the instant wallpaperEngineConfigured turns true; firing the transition
        // first means the peel is already covering that hand-off instead of the
        // image blinking out before the animation begins.
        if (prevPreview && project.preview) {
            const fromStill = prevProject ? root.stillPathFor(prevProject) : "";
            root.requestTransition(fromStill, prevPreview,
                root.stillPathFor(project.id), project.preview);
        }
        project.previousProject = prevProject;
        project.previousPreview = prevPreview;
        Config.options.wallpaperSelector.wallpaperEngine.activeProject = project.id;
        Config.options.wallpaperSelector.wallpaperEngine.activePath = project.path;
        Config.options.wallpaperSelector.wallpaperEngine.activePreview = project.preview;
        // Never expose the previous project's still while the new cache is
        // being generated. ensureStill republishes even when the target cache
        // already exists because the runner exits successfully in that case.
        Config.options.wallpaperSelector.wallpaperEngine.activeStill = "";
        root.ensureStill(project.id, project.path);
        // Start the live runtime immediately, in parallel with theme generation,
        // instead of waiting for the theme process to finish. Otherwise the
        // runtime only spawned ~2s later - well after the ~1.2s peel had ended -
        // leaving a black gap while linux-wallpaperengine was still starting up.
        // Theme colours are independent of the wallpaper surface and catch up on
        // their own.
        root.startRuntime(project);
        if (project.preview) {
            root.enqueueTheme(project);
        }
    }

    function enqueueTheme(project) {
        if (themeProcess.running) {
            // Theme generation is intentionally latest-wins. Starting another
            // command on the same Process would only replace its metadata while
            // the old child kept running, pairing the wrong colors and project.
            themeProcess.pendingProject = project;
            return;
        }
        themeProcess.project = project;
        themeProcess.command = [
            Directories.wallpaperSwitchScriptPath,
            "--mode", Appearance.m3colors.darkmode ? "dark" : "light",
            "--coloronly", "--image", project.preview
        ];
        themeProcess.running = true;
    }

    function startRuntime(project) {
        // The cross-fade is started up front in apply() so it covers the moment
        // the outgoing wallpaper gives way, rather than here after theme
        // generation has already run and swapped the config.
        Quickshell.execDetached([
            root.runnerPath, "apply", project.path,
            String(Config.options.wallpaperSelector.wallpaperEngine.fps),
            Config.options.wallpaperSelector.wallpaperEngine.scaling,
            Config.options.wallpaperSelector.wallpaperEngine.silent ? "true" : "false"
        ]);
        // The runner performs the same initial check after writing its PID.
        // This call keeps the desired state explicit for an already-live runtime.
        root.setPaused(root.fullscreenActive);
        root.applied(project.id);
    }

    // Render (or reuse the cached) full-scene still for a project, then publish
    // it so the background can peel it as an opaque, parallax-able texture.
    function ensureStill(projectId, projectPath, force) {
        const out = root.stillPathFor(projectId);
        if (!out || !projectPath) return;
        const job = { projectId, projectPath, outPath: out, force: force === true };
        if (stillProcess.running) {
            if (stillProcess.projectId === projectId && !job.force)
                return;
            // Still rendering is also latest-wins. Retaining every wallpaper the
            // user briefly hovered/clicked would create a long queue of obsolete
            // five-second GPU jobs before the active wallpaper could be cached.
            root.stillQueue = [job];
            return;
        }
        root.startStillJob(job);
    }

    function startStillJob(job) {
        stillProcess.projectId = job.projectId;
        stillProcess.outPath = job.outPath;
        stillProcess.command = [root.runnerPath, "screenshot", job.projectPath, job.outPath,
            Config.options.wallpaperSelector.wallpaperEngine.scaling, job.force ? "force" : ""];
        stillProcess.running = true;
    }

    function startNextStillJob() {
        if (stillProcess.running || root.stillQueue.length === 0) return;
        const next = root.stillQueue[0];
        root.stillQueue = root.stillQueue.slice(1);
        root.startStillJob(next);
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
        root.stillQueue = [];
        themeProcess.pendingProject = null;
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
            const completedProjectId = stillProcess.projectId;
            const completedOutPath = stillProcess.outPath;
            stillProcess.projectId = "";
            stillProcess.outPath = "";
            // Ignore a stale render if the user has since switched wallpapers.
            if (exitCode === 0 && completedOutPath
                    && completedProjectId === Config.options.wallpaperSelector.wallpaperEngine.activeProject) {
                // Re-set (clear first) so an unchanged path still forces dependent
                // Images to reload now that the file exists.
                Config.options.wallpaperSelector.wallpaperEngine.activeStill = "";
                Config.options.wallpaperSelector.wallpaperEngine.activeStill = completedOutPath;
            }
            Qt.callLater(root.startNextStillJob);
        }
    }

    Process {
        id: themeProcess
        property var project: null
        property var pendingProject: null
        onExited: exitCode => {
            const pendingProject = themeProcess.pendingProject;
            themeProcess.project = null;
            themeProcess.pendingProject = null;
            if (exitCode !== 0)
                root.error = "Wallpaper theme generation failed";
            // The runtime is started up front in apply(); theming only needs to
            // hand off to the latest pending project's colour generation here.
            if (pendingProject) {
                Qt.callLater(() => root.enqueueTheme(pendingProject));
            }
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

    // Lets non-QML wallpaper changes (notably preset application via presets.sh)
    // drive the same still->still cross-fade the in-app selector does. Without
    // this handler the preset's "ipc call wallpaperEngine transition" hit nothing
    // and the wallpaper just cut to black while the new runtime spun up.
    IpcHandler {
        target: "wallpaperEngine"

        function transition(fromStill: string, fromPreview: string, toStill: string, toPreview: string): void {
            root.requestTransition(fromStill, fromPreview, toStill, toPreview);
        }
    }
}
