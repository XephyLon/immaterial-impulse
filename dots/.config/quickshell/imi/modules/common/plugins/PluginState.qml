pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import "gridSizes.js" as GridSizes
import "layout_surfaces.js" as Surfaces

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
            // The lock screen's layout, per screen, present only once that
            // screen has been edited on the Lockscreen tab - an absent screen
            // shows the desktop's layout (layout_surfaces.js, spec §4.3 as
            // amended 2026-08-18).
            lockPositions: {},
            // WHICH widgets the lock screen shows, once the user has picked -
            // null until then, meaning "whatever the desktop shows". An empty
            // map is a lock screen with no widgets on it, which is why absence
            // is a null rather than a `{}` (layout_surfaces.js).
            //
            // No migration accompanies it, for the reason `lockPositions`
            // needed none: the field's ABSENCE is the correct upgrade state.
            // Every existing install lands in "following", where the lock
            // shows exactly the set `lock.showWidgets` shows it today.
            lockPresence: null,
            pluginOptions: {},
            // A widget's own settings on the lock screen, per key: a key
            // stored here is the lock's own, one absent reads through to
            // pluginOptions (layout_surfaces.js). Same no-migration argument
            // as the two above - absence is the correct upgrade state.
            lockOptions: {},
            // Plugin ids whose options/positions/enabled state survive preset
            // application (never captured INTO presets - see presets.sh).
            presetPersist: {},
            // One-shot store migrations that have already run, by name. Same
            // shape as Config's `migrated*` flags, kept here because this is
            // the file being migrated.
            migrations: {}
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

    // ---- two layouts, one store ------------------------------------------
    //
    // Which layout the DESKTOP is drawing right now: the lock's while the
    // session is locked or Edit Mode's Lockscreen tab is filtering the
    // viewport into it, the desktop's otherwise. This is the default surface
    // every position read and write takes, so the widget code that predates
    // the fork keeps its call shape and follows the look automatically.
    //
    // A caller that must NOT follow the look names its surface explicitly.
    // Undo is the one that must not: a closure pushed on the Lockscreen tab
    // and popped on the Desktop tab would otherwise write the lock's position
    // into the desktop's store. It captures `currentSurface` at push time.
    readonly property string currentSurface: GlobalStates.lockLookActive
        ? Surfaces.LOCK : Surfaces.DESKTOP
    // The two surface names, exported so a caller that must name one (undo)
    // spells it the way the module does rather than as a string of its own.
    readonly property string lockSurface: Surfaces.LOCK
    readonly property string desktopSurface: Surfaces.DESKTOP

    // Has this screen's lock layout been edited apart from the desktop's?
    function lockLayoutForked(screenName) {
        return Surfaces.isForked(root.state, screenName);
    }

    // The raw stored entry, or undefined - for callers that need to tell
    // "absent" from "at the default", which position() cannot.
    function rawPosition(pluginId, screenName, surface) {
        return Surfaces.rawPosition(root.state, surface ?? root.currentSurface,
            screenName, pluginId);
    }

    function position(pluginId, screenName, surface) {
        return root.normalizedPosition(root.rawPosition(pluginId, screenName, surface));
    }

    function setPosition(pluginId, screenName, value, surface) {
        if (!pluginId || !screenName) return;
        const nextState = Surfaces.withPosition(root.state, surface ?? root.currentSurface,
            screenName, pluginId, root.normalizedPosition(value));
        nextState.version = root.schemaVersion;
        root.state = nextState;
        writeTimer.restart();
    }

    // A widget's span, per surface (layout_surfaces.js): the desktop's is the
    // `__gridSize` plugin option it has always been; a forked lock screen's
    // lives in the widget's lock record. Same default-surface rule as
    // position(), same explicit-surface rule for undo.
    function gridSize(pluginId, screenName, surface) {
        return Surfaces.rawGridSize(root.state, surface ?? root.currentSurface,
            screenName, pluginId);
    }

    function setGridSize(pluginId, screenName, value, surface) {
        if (!pluginId) return;
        const nextState = Surfaces.withGridSize(root.state, surface ?? root.currentSurface,
            screenName, pluginId, value);
        nextState.version = root.schemaVersion;
        root.state = nextState;
        writeTimer.restart();
    }

    // The whole lock record for a widget on a screen, and its restore - for
    // the re-link's undo, which has to put back position AND span together.
    function lockRecords(screenName) {
        return Object.assign({}, root.state?.lockPositions?.[screenName] ?? {});
    }

    function restoreLockRecords(screenName, records) {
        if (!screenName || !records) return;
        const nextState = Object.assign({}, root.state);
        const store = Object.assign({}, nextState.lockPositions || {});
        store[screenName] = Object.assign({}, records);
        nextState.lockPositions = store;
        nextState.version = root.schemaVersion;
        root.state = nextState;
        writeTimer.restart();
    }

    // ---- the lock's widget choice, forked the same way -------------------
    //
    // Presence is not per screen (`plugins.enabled` is one global list drawn
    // on every monitor), so none of these take a screen name. The desktop's
    // set is Config's, and layout_surfaces.js is pure, so it is handed in
    // here - the one place that can see both files.
    //
    // `Config.options.lock.showWidgets` is NOT consulted here. It is the
    // master gate over the whole feature and belongs to the widget's own
    // visibility expression; folding it in would make "is this widget picked"
    // and "does the lock show widgets at all" one answer, and the drawer's
    // check marks would then all clear the moment the gate went off.
    function lockPresenceForked() {
        return Surfaces.isPresenceForked(root.state);
    }

    function lockWidgetEnabled(pluginId) {
        return Surfaces.lockPresent(root.state, Config.options.plugins.enabled, pluginId);
    }

    function setLockWidgetEnabled(pluginId, enabled) {
        if (!pluginId) return;
        const nextState = Surfaces.withLockPresence(root.state,
            Config.options.plugins.enabled, pluginId, enabled === true);
        nextState.version = root.schemaVersion;
        root.state = nextState;
        writeTimer.restart();
    }

    // The whole choice and its restore - for undo, which has to be able to put
    // back "following" as well as a map, so it carries null through.
    function lockPresenceRecords() {
        return Surfaces.isPresenceForked(root.state)
            ? Object.assign({}, root.state.lockPresence)
            : null;
    }

    function restoreLockPresence(records) {
        const nextState = Object.assign({}, root.state);
        nextState.lockPresence = records ? Object.assign({}, records) : null;
        nextState.version = root.schemaVersion;
        root.state = nextState;
        writeTimer.restart();
    }

    // Re-link the lock's widget choice to the desktop's. A no-op while the two
    // are already linked.
    function resetLockPresence() {
        const nextState = Surfaces.withoutLockPresence(root.state);
        if (nextState === root.state) return;
        nextState.version = root.schemaVersion;
        root.state = nextState;
        writeTimer.restart();
    }

    // Re-link a screen's lock layout to the desktop's: its lock entry goes,
    // and every widget on that screen reads through again. A no-op on a
    // screen that was never forked.
    function resetLockLayout(screenName) {
        const nextState = Surfaces.withoutLockLayout(root.state, screenName);
        if (nextState === root.state) return;
        nextState.version = root.schemaVersion;
        root.state = nextState;
        writeTimer.restart();
    }

    // A widget's option on a surface. Same default-surface rule as
    // position(): a caller that names none - every widget binding, the
    // in-widget knobs - reads the face the desktop is showing, so the
    // resource monitor's rotate button on the Lockscreen tab writes the
    // lock's `vertical`, and the desktop's binding re-evaluates when the
    // look flips because it read currentSurface. Settings names its surface
    // (PluginOptions), and Edit Mode's policy keys are shared whatever is
    // passed (layout_surfaces.js SHARED_OPTION_KEYS).
    function option(pluginId, key, fallback, surface) {
        const value = Surfaces.rawOption(root.state, surface ?? root.currentSurface, pluginId, key);
        return value === undefined ? fallback : value;
    }

    // Has this widget any lock-screen setting of its own?
    function lockOptionsForked(pluginId) {
        return Surfaces.isOptionsForked(root.state, pluginId);
    }

    // Re-link one widget's lock settings to the desktop's.
    function resetLockOptions(pluginId) {
        const nextState = Surfaces.withoutLockOptions(root.state, pluginId);
        if (nextState === root.state) return;
        nextState.version = root.schemaVersion;
        root.state = nextState;
        writeTimer.restart();
    }

    // Desktop-widget panel opacity, resolved against the global transparency
    // switch. Frost and opacity were two independent settings and only frost
    // knew about the toggle: PluginWidget's blur Repeater is gated on
    // `appearance.transparency.enable`, but every widget's panel alpha came
    // from `plugins.blurOpacity` (or a hardcoded literal), which is not. With
    // transparency off that combination removed the blur and kept the 10%
    // panel, leaving each widget a hole onto the sharp wallpaper.
    //
    // Lives here rather than in each widget because it is the same derivation
    // everywhere, and here is the only place that can do both halves of it:
    // PluginState already reads Config (for the toggle and the configured
    // opacity) and already owns the per-plugin option the opt-out needs. The
    // generic designsystem widgets have no PluginWidget root in scope, so a
    // host-side property could not have reached them; a singleton call can,
    // with an empty id for a component that has no plugin identity.
    //
    // `keepTranslucent` is that opt-out, for a widget whose whole point is to
    // be see-through. Same shape as blurEnabled/positionLocked/clickThrough:
    // the manifest seeds the default, PluginState carries the user's override,
    // so a shipped default stays reversible from Settings > Widgets.
    function resolveBackgroundOpacity(baseOpacity, transparencyEnabled, keepTranslucent) {
        return (transparencyEnabled || keepTranslucent) ? baseOpacity : 1;
    }

    // The opacity a widget panel is given when its caller passes none: the
    // shell's own (Settings > Quick's "Shell opacity", the background
    // transparency inverted - what the bar, the sidebars and the dock draw
    // at) when `plugins.followShellOpacity` is on, else the widgets' slider.
    readonly property real configuredBackgroundOpacity: Config.options.plugins.followShellOpacity
        ? 1 - Appearance.backgroundTransparency
        : Config.options.plugins.blurOpacity

    function effectiveBackgroundOpacity(pluginId, baseOpacity, keepTranslucentDefault) {
        return root.resolveBackgroundOpacity(
            baseOpacity === undefined ? root.configuredBackgroundOpacity : baseOpacity,
            Config.options.appearance.transparency.enable,
            root.option(pluginId, "keepTranslucent", keepTranslucentDefault === true));
    }

    readonly property string sizeModeMarker: "migratedSizeMode"

    function migrationRan(name) {
        return root.state?.migrations?.[name] === true;
    }

    // Retires the plugin-declared `sizeMode` option in favour of the host's
    // `__gridSize`: same concept, same "<cols>x<rows>" format, two mechanisms.
    // Without this, upgrading resets the two widgets that declared it to their
    // default size - a visible change to a setting the user chose, with
    // nothing reporting why.
    //
    // Driven by PluginManager rather than run from here, because the manifests
    // are what say which spans are on offer, and they load asynchronously. The
    // marker is the trap AGENT.md names: it records that the pass *ran*, not
    // that it saw the user's data, so burning it against a half-loaded
    // manifest list would lose exactly the size this exists to keep. Hence
    // both guards - the empty list returns without marking, and the caller
    // waits for the manifest loads to settle before calling at all.
    //
    // The per-plugin work itself deletes the old key (gridSizes.migrateSizeMode),
    // so the pass is idempotent on its own - and the walk, not the marker, is
    // what decides whether to run. The marker was the gate once, and it
    // stranded the second wave: weather and currency burned it in 0.6, so
    // when calendar and world-clock crossed from live `sizeMode` to
    // `grid.sizes` months later, their freshly-retired options could never be
    // folded - a stored 3x1 or 1x1 silently reset to the default on upgrade,
    // which is the precise loss this migration exists to prevent. A marker
    // records that a pass ran; only the data can say whether the NEXT pass
    // has work. It is still written, as a record, and still never burned
    // against an empty manifest list.
    //
    // Split in two so the substance can be driven from a TestCase: the whole
    // point of the pass is which options come out the other side, and a
    // function that reads and writes the live singleton can only be tested by
    // mutating it.
    function stateWithSizeModesMigrated(state, manifests) {
        const nextOptions = Object.assign({}, state?.pluginOptions || {});
        for (const manifest of manifests) {
            if (!manifest || !manifest.id) continue;
            const migrated = GridSizes.migrateSizeMode(nextOptions[manifest.id], manifest.grid);
            if (!migrated) continue;
            nextOptions[manifest.id] = migrated;
        }

        const nextMigrations = Object.assign({}, state?.migrations || {});
        nextMigrations[root.sizeModeMarker] = true;

        const nextState = Object.assign({}, state);
        nextState.version = root.schemaVersion;
        nextState.pluginOptions = nextOptions;
        nextState.migrations = nextMigrations;
        return nextState;
    }

    // Whether any manifest offering several spans still has a stored
    // `sizeMode` to fold. Pure, so the gate itself is drivable from a
    // TestCase - the marker-shaped gate this replaces could only be observed
    // by mutating the live singleton.
    function sizeModesPending(state, manifests) {
        if (!Array.isArray(manifests)) return false;
        for (const manifest of manifests) {
            if (!manifest || !manifest.id) continue;
            if (GridSizes.offeredSizes(manifest.grid).length <= 1) continue;
            if (state?.pluginOptions?.[manifest.id]?.sizeMode !== undefined)
                return true;
        }
        return false;
    }

    function migrateSizeModes(manifests) {
        if (!root.ready) return;
        // Returning without marking is the whole guard: a pass over an empty
        // manifest list would burn the marker having read nothing.
        if (!Array.isArray(manifests) || manifests.length === 0) return;
        if (!root.sizeModesPending(root.state, manifests)) return;

        root.state = root.stateWithSizeModesMigrated(root.state, manifests);
        writeTimer.restart();
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

    // null means REMOVE, not store: `option()` falls back only on undefined,
    // so a persisted null would answer every later read in place of the
    // caller's fallback - a key that never existed, materialised on disk.
    // Edit Mode's undo is what reaches this branch: reversing a first-ever
    // commit restores "no stored choice", which has to leave the store the
    // way it found it. On the lock surface the same null is the re-inherit:
    // the lock key goes and the desktop's value reads through again.
    function setOption(pluginId, key, value, surface) {
        if (!pluginId || !key) return;
        const nextState = Surfaces.withOption(root.state, surface ?? root.currentSurface,
            pluginId, key, value);
        nextState.version = root.schemaVersion;
        root.state = nextState;
        writeTimer.restart();
    }

    // The clock carried the shell's only per-surface setting by hand: a
    // second manifest row, `styleLocked`, selected inside the widget. It
    // folds into the lock overlay's `style` here, and what the user SEES on
    // the lock does not change: a stored second style that differs from the
    // desktop's becomes the overlay; one that matches becomes nothing; an
    // absent one was the row's default, "cookie", which differs from any
    // desktop that is not cookie and so becomes an overlay of "cookie" too.
    // Pure, so the three cases are drivable from a TestCase; run once on
    // load, recorded in `migrations` like the sizeMode pass.
    readonly property string clockStyleMarker: "clockStyleLocked"

    function stateWithClockStyleMigrated(state) {
        const clock = state?.pluginOptions?.clock;
        const stored = clock && typeof clock === "object" ? clock : {};
        const desktop = stored.style === undefined ? "cookie" : stored.style;
        const locked = stored.styleLocked === undefined ? "cookie" : stored.styleLocked;
        let next = Object.assign({}, state);
        if (locked !== desktop)
            next = Surfaces.withOption(next, Surfaces.LOCK, "clock", "style", locked);
        if (stored.styleLocked !== undefined)
            next = Surfaces.withOption(next, Surfaces.DESKTOP, "clock", "styleLocked", null);
        const nextMigrations = Object.assign({}, state?.migrations || {});
        nextMigrations[root.clockStyleMarker] = true;
        next.migrations = nextMigrations;
        next.version = root.schemaVersion;
        return next;
    }

    // Data-driven as well as marked (the sizeMode lesson): a `styleLocked`
    // that arrives AFTER the marker - the legacy Config drain below still
    // carries one for a first-run upgrade - is folded whenever it is seen,
    // and the marker alone covers the absent-key case once.
    function migrateClockStyle() {
        const stored = root.state?.pluginOptions?.clock?.styleLocked;
        if (stored === undefined && root.migrationRan(root.clockStyleMarker)) return;
        root.state = root.stateWithClockStyleMigrated(root.state);
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
        // Both halves of the migration ride one batch, so this stops only once
        // every marker it discharges is set. Testing the clock's alone would
        // compute the world clock's timezones and throw them away on every
        // install that has already run the clock half - which is all of them.
        if (Config.options.plugins.migratedDesktopWidgetOptions
            && Config.options.plugins.migratedWorldClockTimezones)
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
        // The drain may have just delivered the clock's legacy styleLocked.
        root.migrateClockStyle();
        writeTimer.restart();

        Config.pendingPluginOptions = ({});
        Config.pendingPluginPositions = ({});
        Config.options.plugins.migratedDesktopWidgetOptions = true;
        Config.options.plugins.migratedWorldClockTimezones = true;
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
                lockPositions: parsed.lockPositions
                    && typeof parsed.lockPositions === "object"
                    && !Array.isArray(parsed.lockPositions)
                    ? parsed.lockPositions
                    : {},
                // Anything that is not a map reads as "following", including a
                // stored list: the fork is the presence of a map, so a shape
                // this cannot use must not be mistaken for one.
                lockPresence: parsed.lockPresence
                    && typeof parsed.lockPresence === "object"
                    && !Array.isArray(parsed.lockPresence)
                    ? parsed.lockPresence
                    : null,
                pluginOptions: parsed.pluginOptions
                    && typeof parsed.pluginOptions === "object"
                    && !Array.isArray(parsed.pluginOptions)
                    ? parsed.pluginOptions
                    : {},
                lockOptions: parsed.lockOptions
                    && typeof parsed.lockOptions === "object"
                    && !Array.isArray(parsed.lockOptions)
                    ? parsed.lockOptions
                    : {},
                presetPersist: parsed.presetPersist
                    && typeof parsed.presetPersist === "object"
                    && !Array.isArray(parsed.presetPersist)
                    ? parsed.presetPersist
                    : {},
                migrations: parsed.migrations
                    && typeof parsed.migrations === "object"
                    && !Array.isArray(parsed.migrations)
                    ? parsed.migrations
                    : {}
            };
            // Inside the try: a file that did not parse is left on disk as
            // it was, not replaced by an empty state carrying a marker.
            root.migrateClockStyle();
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
