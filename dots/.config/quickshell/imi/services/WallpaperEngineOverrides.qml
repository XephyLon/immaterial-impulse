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
            silent: Config.options.wallpaperSelector.wallpaperEngine.silent ?? true,
            volume: Config.options.wallpaperSelector.wallpaperEngine.volume ?? 100,
            audioProcessing: Config.options.wallpaperSelector.wallpaperEngine.audioProcessing ?? true,
            disableMouse: Config.options.wallpaperSelector.wallpaperEngine.disableMouse ?? false,
            disableParallax: Config.options.wallpaperSelector.wallpaperEngine.disableParallax ?? false,
            disableParticles: Config.options.wallpaperSelector.wallpaperEngine.disableParticles ?? false
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

    // Clear the project's ENGINE flags; property edits survive (the module's
    // hasOverride/clearEngineOverrides split - flipping the Custom settings
    // switch off must not eat the user's property tweaks).
    function clearEngineOverrides(projectId) {
        if (!projectId || !WeOverrides.hasOverride(root.overrides, projectId))
            return;
        root.overrides = WeOverrides.clearEngineOverrides(root.overrides, projectId);
        writeTimer.restart();
    }

    // Seed a project's engine flags from the resolved settings, so flipping
    // the Custom settings switch on changes nothing until a control moves.
    function seedOverrides(projectId, effective) {
        if (!projectId)
            return;
        let next = root.overrides;
        next = WeOverrides.setOverride(next, projectId, "fps", effective.fps);
        next = WeOverrides.setOverride(next, projectId, "scaling", effective.scaling);
        next = WeOverrides.setOverride(next, projectId, "silent", effective.silent);
        next = WeOverrides.setOverride(next, projectId, "volume", effective.volume);
        next = WeOverrides.setOverride(next, projectId, "audioProcessing", effective.audioProcessing);
        next = WeOverrides.setOverride(next, projectId, "disableMouse", effective.disableMouse);
        next = WeOverrides.setOverride(next, projectId, "disableParallax", effective.disableParallax);
        next = WeOverrides.setOverride(next, projectId, "disableParticles", effective.disableParticles);
        root.overrides = next;
        writeTimer.restart();
    }

    function hasProperties(projectId) {
        return WeOverrides.hasProperties(root.overrides, projectId);
    }

    // Set (string value) or clear (null) one of the wallpaper's own
    // project.json properties.
    function setProjectProperty(projectId, name, value) {
        if (!projectId || !name)
            return;
        root.overrides = WeOverrides.setProjectProperty(root.overrides, projectId, name, value);
        writeTimer.restart();
    }

    // Take every property edit off the project - back to the wallpaper's own
    // defaults.
    function clearProperties(projectId) {
        if (!WeOverrides.hasProperties(root.overrides, projectId))
            return;
        let next = root.overrides;
        const names = Object.keys(root.overrides[projectId].properties);
        for (const name of names)
            next = WeOverrides.setProjectProperty(next, projectId, name, null);
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
