pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    readonly property int schemaVersion: 2
    readonly property string filePath: `${Directories.shellConfig}/plugin-state.json`
    property var state: root.emptyState()
    property bool ready: false

    function emptyState() {
        return {
            version: root.schemaVersion,
            desktopPositions: {},
            pluginOptions: {},
            // Plugin ids whose options/positions/enabled state survive preset
            // application (never captured INTO presets - see presets.sh).
            presetPersist: {}
        };
    }

    function defaultPosition() {
        return {
            x: 100,
            y: 100,
            placementStrategy: "free"
        };
    }

    function validNumber(value, fallback) {
        return typeof value === "number" && Number.isFinite(value) ? value : fallback;
    }

    function normalizedPosition(value) {
        const fallback = root.defaultPosition();
        if (!value || typeof value !== "object" || Array.isArray(value)) return fallback;
        return {
            x: root.validNumber(value.x, fallback.x),
            y: root.validNumber(value.y, fallback.y),
            placementStrategy: typeof value.placementStrategy === "string"
                ? value.placementStrategy
                : fallback.placementStrategy
        };
    }

    function position(pluginId, screenName) {
        const screens = root.state?.desktopPositions;
        const saved = screens?.[screenName]?.[pluginId];
        return root.normalizedPosition(saved);
    }

    function setPosition(pluginId, screenName, value) {
        if (!pluginId || !screenName) return;

        const nextState = Object.assign({}, root.state);
        const nextScreens = Object.assign({}, nextState.desktopPositions || {});
        const nextScreen = Object.assign({}, nextScreens[screenName] || {});
        nextScreen[pluginId] = root.normalizedPosition(value);
        nextScreens[screenName] = nextScreen;
        nextState.version = root.schemaVersion;
        nextState.desktopPositions = nextScreens;
        root.state = nextState;
        writeTimer.restart();
    }

    function option(pluginId, key, fallback) {
        const value = root.state?.pluginOptions?.[pluginId]?.[key];
        return value === undefined ? fallback : value;
    }

    function presetPersisted(pluginId) {
        return root.state?.presetPersist?.[pluginId] === true;
    }

    function setPresetPersist(pluginId, persisted) {
        if (!pluginId) return;
        const nextState = Object.assign({}, root.state);
        const nextPersist = Object.assign({}, nextState.presetPersist || {});
        if (persisted) nextPersist[pluginId] = true;
        else delete nextPersist[pluginId];
        nextState.version = root.schemaVersion;
        nextState.presetPersist = nextPersist;
        root.state = nextState;
        writeTimer.restart();
    }

    function setOption(pluginId, key, value) {
        if (!pluginId || !key) return;

        const nextState = Object.assign({}, root.state);
        const nextOptions = Object.assign({}, nextState.pluginOptions || {});
        const nextPlugin = Object.assign({}, nextOptions[pluginId] || {});
        nextPlugin[key] = value;
        nextOptions[pluginId] = nextPlugin;
        nextState.version = root.schemaVersion;
        nextState.pluginOptions = nextOptions;
        root.state = nextState;
        writeTimer.restart();
    }

    // A ported built-in's own settings have to end up in this file, but Config
    // cannot write it (and cannot import this module - it is imported *by* it).
    // Config computes the batch instead and parks it on
    // `Config.pendingPluginOptions`; this drains it once both files are loaded.
    //
    // Two rules make it safe to run on any launch:
    //   - a key already present for that plugin wins, so a preference the user
    //     has since set through the widget's settings panel is never clobbered
    //     by the legacy value it was migrated from;
    //   - the marker is written last, so a launch that dies mid-migration
    //     simply migrates again rather than recording a migration that never
    //     landed.
    //
    // Writing the marker last is also why the re-entrancy guard is needed:
    // clearing `Config.pendingPluginOptions` at the end re-emits the very
    // signal this is connected to, while the marker two lines below it is
    // still false. Without the guard the first migration recurses until the JS
    // stack blows - and the RangeError that produces is attributed to whatever
    // unrelated file happens to be next on the stack, so it does not even read
    // as a migration bug.
    property bool drainingConfigOptions: false

    function drainPendingConfigOptions() {
        if (root.drainingConfigOptions)
            return;
        if (!root.ready || !Config.ready)
            return;
        if (Config.options.plugins.migratedDesktopWidgetOptions)
            return;
        const pending = Config.pendingPluginOptions;
        if (!pending || typeof pending !== "object")
            return;

        root.drainingConfigOptions = true;

        const nextState = Object.assign({}, root.state);
        const nextOptions = Object.assign({}, nextState.pluginOptions || {});
        for (const pluginId in pending) {
            const incoming = pending[pluginId];
            if (!incoming || typeof incoming !== "object")
                continue;
            const nextPlugin = Object.assign({}, nextOptions[pluginId] || {});
            for (const key in incoming) {
                if (nextPlugin[key] !== undefined)
                    continue;
                nextPlugin[key] = incoming[key];
            }
            nextOptions[pluginId] = nextPlugin;
        }

        // The legacy position is one pair for the whole desktop, so it seeds
        // every monitor. A monitor that already has a position for the plugin
        // keeps it, same rule as the options above.
        const pendingPositions = Config.pendingPluginPositions || {};
        const nextScreens = Object.assign({}, nextState.desktopPositions || {});
        for (const screen of Quickshell.screens) {
            const nextScreen = Object.assign({}, nextScreens[screen.name] || {});
            let touched = false;
            for (const pluginId in pendingPositions) {
                if (nextScreen[pluginId] !== undefined)
                    continue;
                nextScreen[pluginId] = root.normalizedPosition(pendingPositions[pluginId]);
                touched = true;
            }
            if (touched)
                nextScreens[screen.name] = nextScreen;
        }

        nextState.version = root.schemaVersion;
        nextState.pluginOptions = nextOptions;
        nextState.desktopPositions = nextScreens;
        root.state = nextState;
        writeTimer.restart();

        Config.pendingPluginOptions = ({});
        Config.pendingPluginPositions = ({});
        Config.options.plugins.migratedDesktopWidgetOptions = true;
        root.drainingConfigOptions = false;
    }

    Connections {
        target: Config
        function onPendingPluginOptionsChanged() { root.drainPendingConfigOptions() }
        function onReadyChanged() { root.drainPendingConfigOptions() }
    }

    onReadyChanged: root.drainPendingConfigOptions()

    function snapshot() {
        return JSON.stringify(root.state);
    }

    function replaceSnapshot(text) {
        // An external preset apply must win over any older debounced local
        // write. Cancel both timers before replacing memory and disk together.
        writeTimer.stop();
        reloadTimer.stop();
        root.loadText(text);
        stateFile.setText(JSON.stringify(root.state, null, 2));
    }

    function loadText(text) {
        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
                throw new Error("root value must be an object");

            root.state = {
                version: root.schemaVersion,
                desktopPositions: parsed.desktopPositions
                    && typeof parsed.desktopPositions === "object"
                    && !Array.isArray(parsed.desktopPositions)
                    ? parsed.desktopPositions
                    : {},
                pluginOptions: parsed.pluginOptions
                    && typeof parsed.pluginOptions === "object"
                    && !Array.isArray(parsed.pluginOptions)
                    ? parsed.pluginOptions
                    : {},
                presetPersist: parsed.presetPersist
                    && typeof parsed.presetPersist === "object"
                    && !Array.isArray(parsed.presetPersist)
                    ? parsed.presetPersist
                    : {}
            };
        } catch (error) {
            console.warn("[PluginState] Ignoring invalid state file: " + error);
            root.state = root.emptyState();
        }
        root.ready = true;
    }

    Timer {
        id: reloadTimer
        interval: 100
        onTriggered: stateFile.reload()
    }

    Timer {
        id: writeTimer
        interval: 100
        onTriggered: stateFile.setText(JSON.stringify(root.state, null, 2))
    }

    FileView {
        id: stateFile
        path: root.filePath
        watchChanges: true
        onFileChanged: reloadTimer.restart()
        onLoaded: root.loadText(stateFile.text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.state = root.emptyState();
                root.ready = true;
                writeTimer.restart();
            } else {
                console.warn("[PluginState] Failed to load state file: " + error);
            }
        }
    }


    IpcHandler {
        target: "pluginState"

        function snapshot(): string {
            return root.snapshot();
        }

        function replace(serialized: string): void {
            root.replaceSnapshot(serialized);
        }
    }
}
