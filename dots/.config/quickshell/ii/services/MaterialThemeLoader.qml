pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath
    property string requestedLockWallpaper: ""
    property string requestedLockMode: ""
    property string requestedLockScheme: ""
    property string cachedLockWallpaper: ""
    property string cachedLockMode: ""
    property string cachedLockScheme: ""
    property string cachedLockColors: ""
    property string pendingThemeColors: ""
    property bool pendingThemeIsGenerated: false
    property bool pendingThemeForLockedState: false
    property var activeColorAnimations: []
    // Animating every generated role causes dozens of global bindings to
    // invalidate every frame while the wallpaper and lock blur are moving.
    // Keep the visible structural/accent roles fluid and apply secondary roles
    // atomically; this preserves the perceived theme shift at a bounded cost.
    readonly property var animatedColorRoles: ({
        m3background: true, m3onBackground: true, m3surface: true,
        m3surfaceContainerLow: true, m3surfaceContainer: true,
        m3surfaceContainerHigh: true, m3onSurface: true,
        m3onSurfaceVariant: true, m3outline: true, m3outlineVariant: true,
        m3primary: true, m3onPrimary: true, m3primaryContainer: true,
        m3onPrimaryContainer: true, m3secondary: true, m3onSecondary: true,
        m3secondaryContainer: true, m3onSecondaryContainer: true,
        m3tertiary: true, m3onTertiary: true, m3tertiaryContainer: true,
        m3onTertiaryContainer: true
    })
    readonly property int colorTransitionDuration: Appearance.animation.elementMoveFast.duration
    readonly property bool lockThemeActive: GlobalStates.screenLocked
        && Config.options.background.lockWall !== ""

    function reapplyTheme() {
        themeFileView.reload()
    }

    function restoreNormalTheme() {
        const fileContent = themeFileView.text();
        if (fileContent && fileContent.trim() !== "") {
            root.applyColors(fileContent, true);
        } else {
            // Keep the existing startup/failure recovery behavior when the file
            // has not been loaded yet.
            root.reapplyTheme();
        }
    }

    function stopColorAnimations() {
        colorAnimationCleanup.stop();
        for (const animation of activeColorAnimations) {
            animation.stop();
            animation.destroy();
        }
        activeColorAnimations = [];
    }

    function applyColors(fileContent, animated = false) {
        const json = JSON.parse(fileContent)
        root.stopColorAnimations();
        const animations = [];
        for (const key in json) {
            if (json.hasOwnProperty(key)) {
                // Convert snake_case to CamelCase
                const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                const m3Key = `m3${camelCaseKey}`
                // The generator also emits internal palette-key colors which are not
                // public Appearance roles. Ignore those instead of attempting to add
                // dynamic properties to the fixed QtObject.
                if (Appearance.m3colors[m3Key] === undefined) continue;
                if (animated && root.animatedColorRoles[m3Key] === true
                        && Appearance.m3colors[m3Key] !== json[key]) {
                    const animation = colorAnimationComponent.createObject(root, {
                        target: Appearance.m3colors,
                        property: m3Key,
                        from: Appearance.m3colors[m3Key],
                        to: json[key]
                    });
                    animations.push(animation);
                } else {
                    Appearance.m3colors[m3Key] = json[key]
                }
            }
        }

        if (animated) {
            activeColorAnimations = animations;
            for (const animation of animations) animation.start();
            colorAnimationCleanup.restart();
        } else {
            Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)
        }
    }

    function applyGeneratedColors(fileContent) {
        const colors = {};
        const lines = fileContent.split("\n");
        for (const line of lines) {
            const match = line.match(/^\$([A-Za-z0-9_]+):\s*([^;]+);/);
            if (!match || match[1] === "darkmode" || match[1] === "transparent") continue;
            colors[match[1]] = match[2].trim();
        }
        root.applyColors(JSON.stringify(colors), true);
    }

    function currentMode() {
        return Appearance.m3colors.darkmode ? "dark" : "light";
    }

    function currentScheme() {
        // Pass "auto" through verbatim: generate-colors-venv.sh resolves it via
        // scheme_for_image.py, exactly like switchwall.sh does for the desktop
        // palette. Mapping it to a fixed variant here made the lock palette
        // diverge from the desktop's whenever auto detection picked another one.
        return Config.options.appearance.palette.type;
    }

    function cachedLockThemeMatches(wallpaper, mode, scheme) {
        return cachedLockColors !== ""
            && cachedLockWallpaper === wallpaper
            && cachedLockMode === mode
            && cachedLockScheme === scheme;
    }

    function scheduleTheme(colors, generated, forLockedState) {
        pendingThemeColors = colors;
        pendingThemeIsGenerated = generated;
        pendingThemeForLockedState = forLockedState;
        themeTransitionDelay.restart();
    }

    function prepareLockTheme() {
        const wallpaper = Config.options.background.lockWall;
        if (!Config.ready || wallpaper === "") {
            requestedLockWallpaper = "";
            cachedLockWallpaper = "";
            cachedLockColors = "";
            return;
        }

        const mode = root.currentMode();
        const scheme = root.currentScheme();
        if (root.cachedLockThemeMatches(wallpaper, mode, scheme)) return;
        if (lockThemeProc.running
                && requestedLockWallpaper === wallpaper
                && requestedLockMode === mode
                && requestedLockScheme === scheme) return;

        requestedLockWallpaper = wallpaper;
        requestedLockMode = mode;
        requestedLockScheme = scheme;
        // No --smart here: it silently swaps the scheme to "neutral" for
        // low-chroma images, which the desktop path (switchwall.sh) never
        // does - the same image must yield the same palette locked and
        // unlocked.
        lockThemeProc.command = [
            Quickshell.shellPath("scripts/colors/generate-colors-venv.sh"),
            "--path", wallpaper,
            "--mode", mode,
            "--scheme", scheme
        ];
        lockThemeProc.running = false;
        lockThemeProc.running = true;
    }

    function handleLockStateChange() {
        const wallpaper = Config.options.background.lockWall;
        if (!GlobalStates.screenLocked || wallpaper === "") {
            const normalColors = themeFileView.text();
            if (normalColors && normalColors.trim() !== "")
                root.scheduleTheme(normalColors, false, false);
            else
                root.reapplyTheme();
            root.prepareLockTheme();
            return;
        }

        const mode = root.currentMode();
        const scheme = root.currentScheme();
        if (root.cachedLockThemeMatches(wallpaper, mode, scheme)) {
            root.scheduleTheme(cachedLockColors, true, true);
        } else {
            root.prepareLockTheme();
        }
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            if (!root.lockThemeActive) root.applyColors(themeFileView.text())
        }
    }

    Process {
        id: lockThemeProc
        stdout: StdioCollector { id: lockThemeOutput }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[MaterialThemeLoader] Failed to generate lockscreen colors:", exitCode, exitStatus);
                return;
            }
            if (root.requestedLockWallpaper === Config.options.background.lockWall
                    && root.requestedLockMode === root.currentMode()
                    && root.requestedLockScheme === root.currentScheme()) {
                root.cachedLockWallpaper = root.requestedLockWallpaper;
                root.cachedLockMode = root.requestedLockMode;
                root.cachedLockScheme = root.requestedLockScheme;
                root.cachedLockColors = lockThemeOutput.text;
                if (root.lockThemeActive)
                    root.applyGeneratedColors(root.cachedLockColors);
            }
        }
    }

    Timer {
        id: themeTransitionDelay
        interval: Appearance.animation.elementMoveFast.duration
        onTriggered: {
            if (root.pendingThemeColors === ""
                    || root.pendingThemeForLockedState !== GlobalStates.screenLocked) return;
            if (root.pendingThemeIsGenerated)
                root.applyGeneratedColors(root.pendingThemeColors);
            else
                root.applyColors(root.pendingThemeColors, true);
            root.pendingThemeColors = "";
        }
    }

    Component {
        id: colorAnimationComponent
        ColorAnimation {
            duration: root.colorTransitionDuration
            easing.type: Easing.InOutCubic
        }
    }

    Timer {
        id: colorAnimationCleanup
        interval: root.colorTransitionDuration + 50
        onTriggered: {
            for (const animation of root.activeColorAnimations) animation.destroy();
            root.activeColorAnimations = [];
            Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5);
        }
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { root.handleLockStateChange(); }
    }

    Connections {
        target: Config.options.background
        function onLockWallChanged() {
            root.cachedLockColors = "";
            root.prepareLockTheme();
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) root.prepareLockTheme();
        }
    }

    Component.onCompleted: root.prepareLockTheme()

	FileView { 
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            this.reload()
            delayedFileRead.start()
        }
        onLoadedChanged: {
            const fileContent = themeFileView.text()
            if (!root.lockThemeActive) root.applyColors(fileContent)
        }
        onLoadFailed: root.resetFilePathNextTime();
    }
}
