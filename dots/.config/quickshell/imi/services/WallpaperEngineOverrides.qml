pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import "./we_overrides.js" as WeOverrides

/**
 * Per-project Wallpaper Engine settings, on the PluginState pattern: a raw
 * FileView over its own JSON file, because the map is keyed by runtime
 * project ids and a JsonAdapter only holds declared properties (undeclared
 * children have segfaulted deserialization - see CONTRIBUTING.md).
 *
 * The decisions - per-key fallback to the globals, clear-on-null, the loaded
 * file's sanitation - are services/we_overrides.js, kept pure so
 * tests/tst_we_overrides.qml can drive them. This file owns only the disk.
 */
Singleton {
    id: root

    readonly property string filePath: `${Directories.shellConfig}/wallpaper-engine-overrides.json`

    // Map of project id -> { fps?, scaling?, silent? }. Replaced whole on
    // every change so bindings re-evaluate (a `property var` signals on
    // reassignment only).
    property var overrides: ({})
    property bool ready: false

    // The settings the active project runs at. THE one live derivation -
    // the renderer, the audio routing and the sidebar's controls all read
    // this, so a second spelling of the fallback cannot drift from it.
    readonly property var active: WeOverrides.resolve(
        root.overrides,
        Config.options.wallpaperSelector.wallpaperEngine.activeProject,
        ({
            fps: Config.options.wallpaperSelector.wallpaperEngine.fps,
            scaling: Config.options.wallpaperSelector.wallpaperEngine.scaling,
            silent: Config.options.wallpaperSelector.wallpaperEngine.silent ?? true
        }))

    // The same resolution with the globals as an argument, for tests.
    function resolveFor(projectId, globals) {
        return WeOverrides.resolve(root.overrides, projectId, globals);
    }

    function hasOverride(projectId) {
        return WeOverrides.hasOverride(root.overrides, projectId);
    }

    // Set (value) or clear (null) one key for one project.
    function setOverride(projectId, key, value) {
        if (!projectId)
            return;
        root.overrides = WeOverrides.setOverride(root.overrides, projectId, key, value);
        writeTimer.restart();
    }

    function clearOverrides(projectId) {
        if (!projectId || !WeOverrides.hasOverride(root.overrides, projectId))
            return;
        const next = {};
        for (const id in root.overrides)
            if (id !== projectId)
                next[id] = root.overrides[id];
        root.overrides = next;
        writeTimer.restart();
    }

    Timer {
        id: reloadTimer
        interval: 100
        onTriggered: overridesFile.reload()
    }

    Timer {
        id: writeTimer
        interval: 100
        onTriggered: overridesFile.setText(JSON.stringify(root.overrides, null, 2))
    }

    FileView {
        id: overridesFile
        // The empty path is a real "no file" state, so nothing touches the
        // config directory before the migration gate opens (the Config.qml
        // rule).
        path: Directories.configDirReady ? root.filePath : ""
        watchChanges: true
        onFileChanged: reloadTimer.restart()
        onLoaded: {
            try {
                root.overrides = WeOverrides.sanitize(JSON.parse(overridesFile.text()));
            } catch (e) {
                console.warn("[WallpaperEngineOverrides] unreadable store, keeping in-memory state: " + e);
            }
            root.ready = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.overrides = ({});
                root.ready = true;
            } else {
                console.warn("[WallpaperEngineOverrides] failed to load: " + error);
            }
        }
    }
}
