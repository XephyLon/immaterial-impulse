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
    readonly property bool lockThemeActive: GlobalStates.screenLocked
        && Config.options.background.lockWall !== ""

    function reapplyTheme() {
        themeFileView.reload()
    }

    function restoreNormalTheme() {
        const fileContent = themeFileView.text();
        if (fileContent && fileContent.trim() !== "") {
            root.applyColors(fileContent);
        } else {
            // Keep the existing startup/failure recovery behavior when the file
            // has not been loaded yet.
            root.reapplyTheme();
        }
    }

    function applyColors(fileContent) {
        const json = JSON.parse(fileContent)
        for (const key in json) {
            if (json.hasOwnProperty(key)) {
                // Convert snake_case to CamelCase
                const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                const m3Key = `m3${camelCaseKey}`
                // The generator also emits internal palette-key colors which are not
                // public Appearance roles. Ignore those instead of attempting to add
                // dynamic properties to the fixed QtObject.
                if (Appearance.m3colors[m3Key] !== undefined)
                    Appearance.m3colors[m3Key] = json[key]
            }
        }
        
        Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)
    }

    function applyGeneratedColors(fileContent) {
        const colors = {};
        const lines = fileContent.split("\n");
        for (const line of lines) {
            const match = line.match(/^\$([A-Za-z0-9_]+):\s*([^;]+);/);
            if (!match || match[1] === "darkmode" || match[1] === "transparent") continue;
            colors[match[1]] = match[2].trim();
        }
        root.applyColors(JSON.stringify(colors));
    }

    function generateLockTheme() {
        const wallpaper = Config.options.background.lockWall;
        if (!GlobalStates.screenLocked || wallpaper === "") {
            requestedLockWallpaper = "";
            lockThemeProc.running = false;
            root.restoreNormalTheme();
            return;
        }

        requestedLockWallpaper = wallpaper;
        const configuredScheme = Config.options.appearance.palette.type;
        const scheme = configuredScheme === "auto" ? "scheme-tonal-spot" : configuredScheme;
        lockThemeProc.command = [
            Quickshell.shellPath("scripts/colors/generate_colors_material.py"),
            "--path", wallpaper,
            "--mode", Appearance.m3colors.darkmode ? "dark" : "light",
            "--scheme", scheme,
            "--smart"
        ];
        lockThemeProc.running = false;
        lockThemeProc.running = true;
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
            if (root.lockThemeActive
                    && root.requestedLockWallpaper === Config.options.background.lockWall) {
                root.applyGeneratedColors(lockThemeOutput.text);
            }
        }
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { root.generateLockTheme(); }
    }

    Connections {
        target: Config.options.background
        function onLockWallChanged() {
            if (GlobalStates.screenLocked) root.generateLockTheme();
        }
    }

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
