pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false
    property int readWriteDelay: 50 // milliseconds

    // Forwarded to FileView.blockWrites, which means "block the calling thread
    // until the write completes" - NOT "do not write". The whole block* family
    // names a threading mode, not a permission. Setting this to stop the shell
    // touching config.json looks right, passes review, and writes the file
    // anyway; to actually not write, gate the call sites (see the write timer
    // and onLoadFailed below, which is how configDirTimedOut does it).
    // killDialog.qml is the only user and wants exactly the documented
    // behaviour - see the comment there.
    property bool blockWrites: false

    // Built-in desktop widgets became bundled plugins. Existing installs carry
    // their state in `background.widgets.<key>.enable`, while ported widgets
    // read `plugins.enabled`, which defaults to []. Translate once, then never
    // again.
    //
    // The old keys are deliberately left on disk: the JsonAdapter does not
    // expose keys it has no property for, so they are inert, and leaving them
    // means a user who downgrades still has their settings.
    readonly property var desktopWidgetPluginIds: ({
            // Ported to new bundled plugins of their own.
            "clock": "clock",
            "calendar": "calendar",
            "worldClock": "world-clock",
            "userCard": "user-card",
            "images": "image-converter",
            "visualizer": "visualizer",
            "customImage": "custom-image",
            // Deduplicated: an equivalent plugin already ships, so the
            // built-in is deleted rather than ported and its state maps onto
            // that plugin's existing id. Getting one of these wrong silently
            // drops the widget for anyone who had it on, because the marker
            // records the migration as done either way.
            "resources": "nandoroid_system_monitor",
            "media": "nandoroid_media",
            "weather": "nandoroid_weather",
            "notes": "notes"
        })

    function migrateDesktopWidgetsToPlugins() {
        if (root.options.plugins.migratedDesktopWidgets)
            return;
        const widgets = root.options.background.widgets;
        const enabled = [];
        for (let i = 0; i < root.options.plugins.enabled.length; i++)
            enabled.push(root.options.plugins.enabled[i]);
        for (const key in root.desktopWidgetPluginIds) {
            const id = root.desktopWidgetPluginIds[key];
            if (widgets[key]?.enable && !enabled.includes(id))
                enabled.push(id);
        }
        root.setNestedValue("plugins.enabled", enabled);
        root.setNestedValue("plugins.migratedDesktopWidgets", true);
    }

    // `desktopWidgetPluginIds` above carries exactly one bit per widget:
    // `enable`. Everything else a built-in kept under `background.widgets.<key>`
    // is dropped, which is right for the deduplicated widgets (the surviving
    // plugin is a different program with its own defaults and its own store)
    // and cheap for the ports whose remaining state was one size mode.
    //
    // The clock is the exception, on both counts that matter. It is the only
    // built-in that was on by default, and its four styles look nothing like
    // each other - so an upgrade that keeps `enable` and drops `style` silently
    // repaints every existing desktop, and the user's clock "changes into
    // something else" with no setting they can point at. Its settings therefore
    // migrate too, as a legacy nested path -> flat plugin option key map
    // (plugin options are one flat namespace per plugin:
    // PluginState.option(id, key, default)).
    //
    // Host-owned keys are deliberately absent: `enable` is the line above,
    // `x`/`y`/`placementStrategy` belong to PluginState's per-monitor layout.
    readonly property var desktopClockOptionKeys: ({
            "showOnlyWhenLocked": "showOnlyWhenLocked",
            "style": "style",
            "styleLocked": "styleLocked",
            "color": "color",
            "cookie.aiStyling": "cookieAiStyling",
            "cookie.sides": "cookieSides",
            "cookie.dialNumberStyle": "cookieDialNumberStyle",
            "cookie.hourHandStyle": "cookieHourHandStyle",
            "cookie.minuteHandStyle": "cookieMinuteHandStyle",
            "cookie.secondHandStyle": "cookieSecondHandStyle",
            "cookie.dateStyle": "cookieDateStyle",
            "cookie.timeIndicators": "cookieTimeIndicators",
            "cookie.hourMarks": "cookieHourMarks",
            "cookie.dateInClock": "cookieDateInClock",
            "cookie.constantlyRotate": "cookieConstantlyRotate",
            "cookie.useSineCookie": "cookieUseSineCookie",
            "digital.adaptiveAlignment": "digitalAdaptiveAlignment",
            "digital.showDate": "digitalShowDate",
            "digital.animateChange": "digitalAnimateChange",
            "digital.vertical": "digitalVertical",
            "digital.font.family": "digitalFontFamily",
            "digital.font.weight": "digitalFontWeight",
            "digital.font.width": "digitalFontWidth",
            "digital.font.size": "digitalFontSize",
            "digital.font.roundness": "digitalFontRoundness",
            "pixel.orientation": "pixelOrientation",
            "quote.enable": "quoteEnable",
            "quote.text": "quoteText",
            "quote.followClock": "quoteFollowClock"
        })

    // Plugin options live in plugin-state.json, which is PluginState's file,
    // not Config's - and Config cannot import the plugins module, because that
    // module imports Config back. So this half of the migration only *computes*
    // the batch; PluginState drains `pendingPluginOptions` once both files are
    // loaded and sets the marker only after the values are actually in. A
    // launch that dies in between therefore migrates again next time rather
    // than recording a migration that never happened.
    //
    // The marker is its own key rather than reusing `migratedDesktopWidgets`:
    // installs that already ran the enable-only migration would otherwise be
    // permanently excluded from the settings half.
    property var pendingPluginOptions: ({})

    // The clock's position moves too, for the same reason its style does. Every
    // other port let the first enable land on the host's generic x/y 100,
    // because those widgets were off by default - being asked to place a widget
    // you just switched on is not a regression. The clock is on already and has
    // been sitting where the user put it, possibly for as long as the install
    // has existed, so the same reset would silently *move* something rather
    // than place something new.
    //
    // The legacy position is one pair for the whole desktop while PluginState
    // keeps one per monitor, so the drain seeds every monitor with it.
    property var pendingPluginPositions: ({})

    // The world clock is the second widget whose data has to travel, and the
    // last `background.widgets.*` key anything wrote at runtime: its four
    // timezones. Every other port's data was either a size mode (regenerated
    // from a default nobody notices) or a dedup onto a plugin with its own
    // store, but a picked timezone is typed-in state - drop it and the card
    // silently goes back to Sydney/Tokyo/London/New York.
    //
    // Its marker is separate from `migratedDesktopWidgetOptions` for the same
    // reason that one is separate from `migratedDesktopWidgets`: every install
    // that has launched this branch once already has the clock marker set, and
    // reusing it would exclude all of them from this half. Both markers ride
    // the same pending batch, so each half only contributes what its own marker
    // still says is outstanding.
    function migrateDesktopWidgetOptionsToPlugins() {
        const options = {};
        const positions = {};

        if (!root.options.plugins.migratedDesktopWidgetOptions) {
            const clock = root.options.background.widgets.clock;
            if (clock) {
                positions["clock"] = {
                    x: clock.x,
                    y: clock.y,
                    placementStrategy: clock.placementStrategy
                };
                const values = {};
                for (const path in root.desktopClockOptionKeys) {
                    const parts = path.split(".");
                    let node = clock;
                    for (let i = 0; i < parts.length; i++) {
                        if (node === undefined || node === null)
                            break;
                        node = node[parts[i]];
                    }
                    if (node === undefined || node === null)
                        continue;
                    values[root.desktopClockOptionKeys[path]] = node;
                }
                options["clock"] = values;
            }
        }

        if (!root.options.plugins.migratedWorldClockTimezones) {
            const legacy = root.options.background.widgets.worldClock?.timezones;
            if (legacy && legacy.length > 0) {
                // `list<string>` is not a JS array, and PluginState hands the
                // value straight to JSON.stringify - copy it out element by
                // element, or the file gets an object with numeric keys that
                // `Array.isArray` then rejects on the way back in.
                const zones = [];
                for (let i = 0; i < legacy.length; i++)
                    zones.push(legacy[i]);
                options["world-clock"] = { "timezones": zones };
            }
        }

        root.pendingPluginPositions = positions;
        root.pendingPluginOptions = options;
    }

    // Settings arriving from end-4/dots-hyprland or pctrade/end4-pC. The full
    // old-key -> new-key table, including every key that was *removed* rather
    // than renamed and why, is docs/UPSTREAM_MIGRATION.md - keep the two in
    // step, a migration nobody can audit is worse than none.
    //
    // This takes the raw parsed config rather than `root.options`, because the
    // keys it has to read are exactly the ones `root.options` cannot see: a
    // JsonAdapter does not expose a key it has no property for. `bar.shadow`
    // reading `undefined` is precisely the silent loss being fixed here, so
    // reading the file's own text is the only way to see what the user had.
    //
    // Pure on purpose: it computes the writes and makes none, so the mapping
    // can be tested against fabricated upstream configs (tst_upstream_migration)
    // instead of against this file's source text.
    function planUpstreamKeyMigration(legacy) {
        const plan = {};
        if (!legacy || typeof legacy !== "object")
            return plan;

        // A value, not a key, so the adapter carries it across intact and then
        // nothing matches it. "ii" is aliased at read time in shell.qml; the
        // waffle family was never ported, so a config naming it activates no
        // panel loader at all and the desktop comes up empty with no error.
        // Anything else is someone's own value and not ours to overwrite.
        if (legacy.panelFamily === "ii" || legacy.panelFamily === "waffle")
            plan["panelFamily"] = "imi";

        // bar.floatStyleShadow -> bar.shadow. Upstream drew the shadow only
        // under the Float corner style; ours draws it under every style that
        // paints a background. The flag defaults to true up there, so copying
        // it straight across would switch on a shadow that most arriving users
        // have never seen. Migrate what was on screen, not what was on disk.
        const legacyBar = legacy.bar;
        if (legacyBar && typeof legacyBar.floatStyleShadow === "boolean")
            plan["bar.shadow"] = legacyBar.floatStyleShadow && legacyBar.cornerStyle === 1;

        return plan;
    }

    // Compute, then write, then mark - the ordering `migrateDesktopWidgetOptionsToPlugins`
    // already argues for. A config we could not even parse is left unmarked so
    // the next launch tries again, rather than recording a migration that never
    // happened; a config we did inspect is marked even when it needed nothing,
    // so the parse does not repeat forever.
    function migrateUpstreamKeys(rawConfigText) {
        if (root.options.migratedUpstreamSchema)
            return;
        let legacy;
        try {
            legacy = JSON.parse(rawConfigText);
        } catch (e) {
            return;
        }
        const plan = root.planUpstreamKeyMigration(legacy);
        for (const key in plan)
            root.setNestedValue(key, plan[key]);
        root.setNestedValue("migratedUpstreamSchema", true);
    }

    function setNestedValue(nestedKey, value) {
        let keys = nestedKey.split(".");
        let obj = root.options;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Convert value to correct type using JSON.parse when safe
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }

        obj[keys[keys.length - 1]] = convertedValue;
    }

    // Issue #69: older installs seeded hyprland.input.kbOptions =
    // "grp:win_space_toggle" before the layout switch became a compositor bind
    // (hypr/hyprland/keybinds.lua). xkb grp: toggles match modifiers loosely,
    // so leaving it set breaks Super+Space *and* Super+Alt+Space: the former
    // fires the xkb toggle and the bind, two switches that cancel out, so the
    // OSD reports a layout change that did not happen; the latter switches the
    // layout on top of toggling the window float.
    //
    // Unconditional, and deliberately not behind a persisted "already
    // migrated" marker - that is the version that shipped and did not fix
    // anything. A marker records that the check ran, not that the value was
    // ever seen, and the two come apart on exactly the installs this targets:
    // when the config-directory migration declines (see
    // scripts/migrate-config-dir.sh), Config loads the installer's default,
    // where kbOptions is already "", the marker is burned against it, and the
    // user's real config - grp: and all - arrives afterwards, permanently out
    // of reach. There is nothing to protect with a marker either way, because
    // "grp:win_space_toggle" is not a value this shell can hold legitimately:
    // the settings control offers only "" and grp:alt_shift_toggle.
    function clearStaleKbOptions() {
        if (root.options.hyprland.input.kbOptions === "grp:win_space_toggle") {
            root.options.hyprland.input.kbOptions = "";
            console.log("[Config] cleared a stale hyprland.input.kbOptions = grp:win_space_toggle (issue #69)");
        }

        // Deliberately outside the check above, because config.json is not what
        // Hyprland reads. The option reaches the compositor only through the
        // generated shellOverrides/main.lua, and nothing rewrites that file at
        // startup - the Hyprland settings page re-applies it from
        // Component.onCompleted, and that page is an on-demand Loader. So the
        // two can disagree, and the disagreement is not hypothetical: the
        // config-only fix that shipped first cleared config.json and left the
        // lua line untouched, which is exactly the population still broken.
        // Keying this purge on the config value would skip every one of them.
        //
        // --reset-if removes the managed line only while it still holds the
        // stale value, so running it on every load is safe: it cannot touch a
        // grp:alt_shift_toggle the user has since chosen, and it does not
        // rewrite the file - and so does not make Hyprland reload - when there
        // is nothing to remove.
        Quickshell.execDetached([
            "python3", Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py"),
            "--file", FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/main.lua`),
            "--reset-if", "input:kb_options", "grp:win_space_toggle"
        ]);
    }

    // The config directory migration has to have finished before this file is
    // read or written - see Directories.configDirReady. An unset path is a
    // real "no file" state in Quickshell: it emits neither `loaded` nor
    // `loadFailed`, and `writeAdapter()` on it writes nothing, so gating the
    // path holds the whole adapter off the disk rather than merely delaying a
    // read.
    //
    // Latched, and it also means "never write this session": the only way it
    // gets set is the watchdog giving up on a migration that is still running,
    // and a write into a half-migrated directory is the thing the gate exists
    // to prevent. `FileView.blockWrites` is not this - it makes writes
    // synchronous, it does not suppress them.
    property bool configDirTimedOut: false
    readonly property bool configDirReady: Directories.configDirReady || root.configDirTimedOut

    // A gate that can hang is a shell that never loads its settings: every
    // settings page Loader is gated on `ready`. Come up anyway, but read-only.
    // Nothing is guessed at and nothing on disk is touched; the user is told,
    // and the next launch retries the migration from an unchanged directory.
    Timer {
        id: configDirWatchdog
        interval: 10000
        running: !Directories.configDirReady
        onTriggered: {
            console.log(`[Config] scripts/migrate-config-dir.sh has not finished after ${configDirWatchdog.interval}ms. Loading ${root.filePath} read-only: settings changed this session will NOT be saved, and nothing in the config directory will be modified.`);
            root.configDirTimedOut = true;
        }
    }

    Timer {
        id: fileReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.reload()
        }
    }

    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            if (root.configDirTimedOut)
                return;
            configFileView.writeAdapter()
        }
    }

    FileView {
        id: configFileView
        path: root.configDirReady ? root.filePath : ""
        watchChanges: true
        blockWrites: root.blockWrites
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: {
            // Before `ready`, and before every other migration: the rest read
            // `root.options`, while this one works off the raw file text
            // because the keys it converts are exactly the ones the adapter
            // dropped. It can also rewrite panelFamily, which decides which
            // panel family loads at all.
            root.migrateUpstreamKeys(text());
            root.ready = true;
            root.clearStaleKbOptions();
            root.migrateDesktopWidgetsToPlugins();
            root.migrateDesktopWidgetOptionsToPlugins();
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                // Creating the file here is exactly the write that used to
                // kill the directory migration, so a timed-out gate must not
                // do it - the migration is still running and may be about to
                // put the user's own config at this path.
                if (!root.configDirTimedOut)
                    writeAdapter();
                else
                    root.ready = true;
                return;
            }
            // Any other read failure - bad permissions, an unreadable mount,
            // a device error - must not leave `ready` false forever. Every
            // settings page Loader is gated on it, so a config file that
            // exists but cannot be read blanks the entire settings content
            // pane while the navigation rail still renders, which reads as
            // "the app is broken" rather than "your config is unreadable".
            // Fall back to the built-in defaults instead.
            console.log(`[Config] Could not read ${root.filePath} (error ${error}); continuing with defaults.`);
            root.ready = true;
        }

        JsonAdapter {
            id: configOptionsJsonAdapter

            property string panelFamily: "imi"

            // Set once a config written against the upstream schema
            // (end-4/dots-hyprland, pctrade/end4-pC) has been converted. It is
            // the only usable "this file has not been converted yet" signal:
            // the installer's has_legacy_config() tests for the old *directory*,
            // which is already gone for anyone whose directory migration ran
            // before this existed - exactly the users who still need this.
            property bool migratedUpstreamSchema: false

            property JsonObject plugins: JsonObject {
                property list<string> enabled: []
                // Gates the in-shell plugin store UI (Browse plugins button,
                // update badges). Off until the public registry goes live;
                // config-file-only, no settings toggle on purpose.
                property bool storeEnabled: false
                property real blurOpacity: 0.1
                // How desktop widgets frost their background over the wallpaper:
                //   "tint" - a translucent palette-tinted panel (cheap, no blur)
                //   "blur" - a true in-shell blur of the wallpaper region behind
                //            the widget (samples the live Wallpaper Engine surface
                //            or the static image)
                property string frostMode: "blur"
                // Set once the built-in desktop widgets have been
                // translated into `enabled`. Without it the migration
                // re-adds a widget on every launch and the user can never
                // turn one off.
                property bool migratedDesktopWidgets: false
                // Set once the clock's own settings have been translated into
                // plugin options. Separate from the marker above on purpose:
                // the enable-only migration shipped first, so installs that
                // already ran it would otherwise never get their clock style,
                // fonts or quote carried across. PluginState sets this, and
                // only after the values have actually reached its file.
                property bool migratedDesktopWidgetOptions: false
                // Set once the world clock's timezone list has been translated
                // into a plugin option. Its own key for the same reason again:
                // every install that has launched this branch once already has
                // the marker above set, and those are exactly the installs whose
                // timezones still need carrying across.
                property bool migratedWorldClockTimezones: false
            }

            property JsonObject policies: JsonObject {
                property int ai: 1 // 0: No | 1: Yes | 2: Local
                property int weeb: 1 // 0: No | 1: Open | 2: Closet
            }

            property JsonObject ai: JsonObject {
                property string systemPrompt: "## Style\n- Use casual tone, don't be formal!\n- Always be brief and to the point, unless asked otherwise\n- Don't repeat the user's question\n- Be approachable: Avoid using overly complicated, domain-specific terms and provide analogies when asked to explain a concept\n\n## Context (ignore when irrelevant)\n- You are a helpful and inspiring sidebar assistant on a {DISTRO} Linux system\n- Desktop environment: {DE}\n- Current date & time: {DATETIME}\n- Focused app: {WINDOWCLASS}\n\n## Presentation\n- Use Markdown features in your response: \n  - **Bold** text to **highlight keywords** in your response\n  - **Split long information into small sections** with h2 headers and a relevant emoji at the start of it (for example `## 🐧 Linux`). Bullet points are preferred over long paragraphs, unless you're offering writing support or instructed otherwise by the user.\n- Asked to compare different options? You should firstly use a table to compare the main aspects, then elaborate or include relevant comments from online forums *after* the table. Make sure to provide a final recommendation for the user's use case!\n- Use LaTeX formatting for mathematical and scientific notations whenever appropriate. Enclose all LaTeX '$$' delimiters. NEVER generate LaTeX code in a latex block unless the user explicitly asks for it. DO NOT use LaTeX for regular documents (resumes, letters, essays, CVs, etc.).\n\nThanks!\n"
                property string tool: "functions" // search, functions, or none
                property list<var> customProviders: [
                    {
                        "enabled": false,
                        "name": "OpenRouter",
                        "baseUrl": "https://openrouter.ai/api/v1"
                    }
                ]
                property list<var> extraModels: [
                    {
                        "api_format": "openai", // Most of the time you want "openai". Use "gemini" for Google's models
                        "description": "This is a custom model. Edit the config to add more! | Anyway, this is DeepSeek R1 Distill LLaMA 70B",
                        "endpoint": "https://openrouter.ai/api/v1/chat/completions",
                        "homepage": "https://openrouter.ai/deepseek/deepseek-r1-distill-llama-70b:free", // Not mandatory
                        "icon": "spark-symbolic", // Not mandatory
                        "key_get_link": "https://openrouter.ai/settings/keys", // Not mandatory
                        "key_id": "openrouter",
                        "model": "deepseek/deepseek-r1-distill-llama-70b:free",
                        "name": "Custom: DS R1 Dstl. LLaMA 70B",
                        "requires_key": true
                    }
                ]
            }

            property JsonObject appearance: JsonObject {
                // "" = follow the system icon theme; otherwise the directory
                // name of an installed icon theme (see IconThemes.qml).
                property string iconTheme: ""
                property bool extraBackgroundTint: true
                property int fakeScreenRounding: 2 // 0: None | 1: Always | 2: When not fullscreen
                // Automatic dark/light switching. "off" = manual only.
                property JsonObject autoTheme: JsonObject {
                    property string mode: "off" // off | sunset | fixed
                    property string lightTime: "07:00" // HH:MM (fixed mode)
                    property string darkTime: "19:00" // HH:MM (fixed mode)
                }
                property JsonObject fonts: JsonObject {
                    property string main: "Google Sans Flex"
                    property string numbers: "Google Sans Flex"
                    property string title: "Google Sans Flex"
                    property string iconNerd: "JetBrains Mono NF"
                    property string monospace: "JetBrains Mono NF"
                    property string reading: "Readex Pro"
                    property string expressive: "Space Grotesk"
                }
                property JsonObject transparency: JsonObject {
                    property bool enable: false
                    property bool automatic: true
                    property real backgroundTransparency: 0.11
                    property real contentTransparency: 0.57
                }
                property JsonObject terminal: JsonObject {
                    property JsonObject background: JsonObject {
                        property bool enabled: false
                        property string imagePath: ""
                        property string layout: "tiled"
                        property real opacity: 0.18
                    }
                }
                property JsonObject wallpaperTheming: JsonObject {
                    property bool enableAppsAndShell: true
                    property bool enableQtApps: true
                    property bool enableTerminal: true
                    property JsonObject terminalGenerationProps: JsonObject {
                        property real harmony: 0.6
                        property real harmonizeThreshold: 100
                        property real termFgBoost: 0.35
                        property bool forceDarkMode: false
                    }
                }
                // Sync RGB peripherals to the generated accent color via the
                // OpenRGB CLI (see services/OpenRgb.qml). Off by default:
                // not everyone has RGB devices or openrgb installed.
                property JsonObject openrgb: JsonObject {
                    property bool enable: false
                    // Device names (as printed by `openrgb --list-devices`)
                    // to leave out of the color sync.
                    property list<string> excludedDevices: []
                    // "accent" follows the Material You accent (default);
                    // "monitor" samples the focused monitor's dominant color
                    // (ambient bias lighting, needs grim).
                    property string colorSource: "accent"
                    // With "monitor": only sample while a fullscreen client is
                    // on the focused monitor, falling back to the accent
                    // otherwise. false samples continuously.
                    property bool monitorFullscreenOnly: true
                    property int monitorPollInterval: 200 // ms between samples
                    // Minimum summed per-channel difference (0-765) before a
                    // sampled color is written; below it the sample is dropped.
                    property int monitorColorDelta: 12
                    // Blend each sample halfway toward the previous applied
                    // color instead of snapping on hard scene cuts.
                    property bool monitorSmooth: true
                    // Device types (as printed by `openrgb --list-devices`)
                    // the ambient loop never writes to. GPU RGB rides the
                    // graphics card's i2c bus - streaming to it mid-game
                    // stalls rendering. The accent sync still covers these.
                    property list<string> monitorExcludedTypes: ["GPU"]
                }
                property JsonObject palette: JsonObject {
                    property string type: "auto" // Allowed: auto, scheme-content, scheme-expressive, scheme-fidelity, scheme-fruit-salad, scheme-monochrome, scheme-neutral, scheme-rainbow, scheme-tonal-spot
                    property string accentColor: ""
                }
                // Shared defaults for Material 3 Expressive plugin widgets.
                property JsonObject clockFonts: JsonObject {
                    property string desktopTimeFont: "Google Sans Flex"
                    property string lockscreenTimeFont: "Google Sans Flex"
                }
                property JsonObject clock: JsonObject {
                    property string style: "digital"
                    property string styleLocked: "digital"
                    property bool showOnDesktop: true
                    property bool showDesktopDate: true
                    property bool showLockscreenDate: true
                    property bool useSameStyle: true
                    property int offsetX: 0
                    property int offsetY: -50
                    property JsonObject digital: JsonObject { property bool isVertical: false; property string colorStyle: "primary"; property int fontSize: 84; property int dateFontSize: 24; property int dateGap: 4; property bool hideAmPm: false; property string alignment: "center" }
                    property JsonObject digitalLocked: JsonObject { property bool isVertical: false; property string colorStyle: "primary"; property int fontSize: 84; property int dateFontSize: 24; property int dateGap: 4; property bool hideAmPm: false; property string alignment: "center" }
                    property JsonObject analog: JsonObject { property bool constantlyRotate: false; property string backgroundStyle: "shape"; property int sides: 12; property string backgroundShape: "Circle"; property string shape: "Circle"; property bool showMarks: true; property bool hourMarks: false; property bool timeIndicators: false; property string dateStyle: "bubble"; property string handStyle: "modern"; property string hourHandStyle: "fill"; property string minuteHandStyle: "bold"; property string secondHandStyle: "dot"; property string dialStyle: "dots"; property int size: 240 }
                    property JsonObject analogLocked: JsonObject { property bool constantlyRotate: false; property string backgroundStyle: "shape"; property int sides: 12; property string backgroundShape: "Circle"; property string shape: "Circle"; property bool showMarks: true; property bool hourMarks: false; property bool timeIndicators: false; property string dateStyle: "bubble"; property string handStyle: "modern"; property string hourHandStyle: "fill"; property string minuteHandStyle: "bold"; property string secondHandStyle: "dot"; property string dialStyle: "dots"; property int size: 240 }
                    property JsonObject code: JsonObject { property string valueColorStyle: "primary"; property string keywordColorStyle: "tertiary"; property string blockColorStyle: "primary"; property int fontSize: 18; property string blockType: "js"; property string fontFamily: "JetBrains Mono NF" }
                    property JsonObject codeLocked: JsonObject { property string valueColorStyle: "primary"; property string keywordColorStyle: "tertiary"; property string blockColorStyle: "primary"; property int fontSize: 18; property string blockType: "js"; property string fontFamily: "JetBrains Mono NF" }
                    property JsonObject text: JsonObject { property int fontSize: 42; property int dateFontSize: 18; property string alignment: "center"; property string timeColorStyle: "onSurface"; property string dateColorStyle: "primary" }
                    property JsonObject textLocked: JsonObject { property int fontSize: 42; property int dateFontSize: 18; property string alignment: "center"; property string timeColorStyle: "onSurface"; property string dateColorStyle: "primary" }
                    property JsonObject pill: JsonObject { property int size: 120; property bool isVertical: false; property bool showBackground: true; property string timeColorStyle: "onLayer0"; property string dateColorStyle: "primary"; property string pillColorStyle: "surfaceContainerHigh" }
                    property JsonObject pillLocked: JsonObject { property int size: 120; property bool isVertical: false; property bool showBackground: true; property string timeColorStyle: "onLayer0"; property string dateColorStyle: "primary"; property string pillColorStyle: "surfaceContainerHigh" }
                }
                property JsonObject atAGlance: JsonObject { property bool showGreeting: true; property bool showDate: true; property bool showEvents: true; property bool showQuote: true; property real customWidth: 0; property string alignment: "left"; property string fontFamily: ""; property int fontSize: 24; property string greetingColorStyle: "primary"; property string dateColorStyle: "onLayer1"; property string quoteColorStyle: "onLayer1"; property bool locked: false }
                property JsonObject mediaWidget: JsonObject { property bool locked: false; property bool showLyrics: false }
                property JsonObject systemMonitor: JsonObject { property bool locked: false; property bool vertical: false; property int updateInterval: 3000 }
                property JsonObject weatherWidget: JsonObject { property bool locked: false; property string sizeMode: "3x1" }
                property JsonObject currencyWidget: JsonObject { property bool locked: false; property string sizeMode: "2x1"; property string baseCurrency: "USD"; property string quote1: "EUR"; property string quote2: "GBP"; property string quote3: "JPY"; property string quote4: "CAD" }
                property JsonObject lyrics: JsonObject { property bool showFloatingLyrics: false; property bool lyricsUseRomaji: false }
            }

            property JsonObject audio: JsonObject {
                // Values in %
                property JsonObject protection: JsonObject {
                    // Prevent sudden bangs
                    property bool enable: false
                    property real maxAllowedIncrease: 10
                    property real maxAllowed: 99
                }
            }

            property JsonObject profile: JsonObject {
                property string avatarPath: ""
                property string avatarPicture: ""
                property string descriptionText: "::distro::"
                property string displayName: ""

            }

            property JsonObject hyprland: JsonObject {
                property JsonObject animations: JsonObject {
                    property string animation: "normal"
                    property bool enable: true
                }
                property JsonObject autostartApps: JsonObject {
                    property bool enable: false
                    property list<var> apps: []
                }
                property JsonObject decoration: JsonObject {
                    property int rounding: 22
                    property real activeOpacity: 1.0
                    property real inactiveOpacity: 0.9
                    property JsonObject blur: JsonObject {
                        // Defaults mirror the effective decoration:blur values this
                        // setup already runs, so exposing them in settings cannot
                        // change how the compositor looks on first open.
                        property bool enabled: true
                        property int size: 1
                        property int passes: 3
                        property bool ignoreOpacity: true
                        property bool newOptimizations: true
                        property bool xray: false
                        property real noise: 0.05
                        property real contrast: 0.89
                        property real brightness: 1.0
                        property real vibrancy: 0.0
                        property real vibrancyDarkness: 0.5
                        property bool special: true
                        property bool popups: false
                        property real popupsIgnorealpha: 0.6
                        property bool inputMethods: true
                        property real inputMethodsIgnorealpha: 0.8
                    }
                    property JsonObject shadow: JsonObject {
                        property bool enabled: true
                        property int range: 4
                    }
                }
                property JsonObject general: JsonObject {
                    property int borderSize: 1
                    property int gapsIn: 2
                    property int gapsOut: 5
                    property string layout: "dwindle"
                }
                property JsonObject input: JsonObject {
                    property string kbLayout: "us"
                    property string kbOptions: ""   // xkb layout-switch shortcut, e.g. grp:alt_shift_toggle / grp:win_space_toggle
                    property bool numlock: true
                    property int repeatDelay: 250
                    property int repeatRate: 35
                    property int followMouse: 1
                    property JsonObject touchpad: JsonObject {
                        property bool naturalScroll: false
                        property bool disableWhileTyping: true
                        property bool clickfingerBehavior: false
                        property real scrollFactor: 0.7
                    }
                }
            }

            property JsonObject apps: JsonObject {
                property string bluetooth: "kcmshell6 kcm_bluetooth"
                property string changePassword: "kitty -1 --hold=yes fish -i -c 'passwd'"
                property string network: "kcmshell6 kcm_networkmanagement"
                property string manageUser: "kcmshell6 kcm_users"
                property string networkEthernet: "kcmshell6 kcm_networkmanagement"
                property string taskManager: "plasma-systemmonitor --page-name Processes"
                property string terminal: "kitty -1" // This is only for shell actions
                property string update: "kitty -1 --hold=yes fish -i -c 'pkexec pacman -Syu'"
                property string volumeMixer: `~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"`
            }

            property JsonObject cheatsheet: JsonObject {
                // Use a nerdfont to see the icons
                // 0: 󰖳  | 1: 󰌽 | 2: 󰘳 | 3:  | 4: 󰨡
                // 5:  | 6:  | 7: 󰣇 | 8:  | 9:
                // 10:  | 11:  | 12:  | 13:  | 14: 󱄛
                property string superKey: ""
                property bool useMacSymbol: false
                property bool splitButtons: false
                property bool useMouseSymbol: false
                property bool useFnSymbol: false
                property JsonObject fontSize: JsonObject {
                    property int key: Appearance.font.pixelSize.smaller
                    property int comment: Appearance.font.pixelSize.smaller
                }
            }

            property JsonObject background: JsonObject {
                property string lockWall: ""
                // Wallpaper Engine project path for the lock wallpaper. When set,
                // the lock wallpaper is that live WE project (takes precedence over
                // the static lockWall image); the WE surface switches to it on lock
                // and back to the desktop project on unlock.
                property string lockWallEngine: ""
                property bool widgetsLocked: false
                property bool showGrid: true
                property bool showSnapLines: true
                property JsonObject widgets: JsonObject {
                    property JsonObject clock: JsonObject {
                        property bool enable: true
                        property bool showOnlyWhenLocked: false
                        property string placementStrategy: "leastBusy" // "free", "leastBusy", "mostBusy"
                        property real x: 100
                        property real y: 100
                        property string style: "cookie"        // Options: "cookie", "digital"
                        property string color: ""
                        property string styleLocked: "cookie"  // Options: "cookie", "digital"
                        property JsonObject cookie: JsonObject {
                            property bool aiStyling: false
                            property int sides: 14
                            property string dialNumberStyle: "full"   // Options: "dots" , "numbers", "full" , "none"
                            property string hourHandStyle: "fill"     // Options: "classic", "fill", "hollow", "hide"
                            property string minuteHandStyle: "medium" // Options "classic", "thin", "medium", "bold", "hide"
                            property string secondHandStyle: "dot"    // Options: "dot", "line", "classic", "hide"
                            property string dateStyle: "bubble"       // Options: "border", "rect", "bubble" , "hide"
                            property bool timeIndicators: true
                            property bool hourMarks: false
                            property bool dateInClock: true
                            property bool constantlyRotate: false
                            property bool useSineCookie: false
                        }
                        property JsonObject digital: JsonObject {
                            property bool adaptiveAlignment: true
                            property bool showDate: true
                            property bool animateChange: true
                            property bool vertical: false
                            property JsonObject font: JsonObject {
                                property string family: "Google Sans Flex"
                                property real weight: 350
                                property real width: 100
                                property real size: 90
                                property real roundness: 0
                            }
                        }
                        property JsonObject pixel: JsonObject {
                            property string orientation: "vertical"
                        }
                        property JsonObject quote: JsonObject {
                            property bool enable: false
                            property string text: ""
                            property bool followClock: false
                        }
                    }
                    property JsonObject weather: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                        property string sizeMode: "1x3"
                    }

                    property JsonObject calendar: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                        property string sizeMode: "2x2"
                    }
                    property JsonObject worldClock: JsonObject {
                        property bool enable: false
                        property list<string> timezones: ["Australia/Sydney", "Asia/Tokyo", "Europe/London", "America/New_York"]
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property string sizeMode: "2x2" 
                    }

                    property JsonObject notes: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                    }

                    property JsonObject userCard: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                    }

                    property JsonObject images: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                    }

                    property JsonObject visualizer: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 0
                        property real y: 0
                    }

                    property JsonObject customImage: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property string path: ""
                        property string shape: "Cookie4Sided"
                        property real size: 200
                    }

                    property JsonObject resources: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property bool vertical: false
                    }

                    property JsonObject media: JsonObject {
                        property bool enable: false
                        property bool showControls: true
                        property bool showLyrics: false
                        property bool showTitles: true
                        property string backgroundShape: "Cookie4Sided"
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 800
                        property real y: 500
                    }
                }
                property list<string> screenList: [] 
                property string wallpaperPath: ""
                property bool centeredWallpaper: false
                property string centeredWallpaperShape: "Cookie7Sided"
                property int centeredWallpaperSize: 400
                property string centeredWallpaperColor: "primaryContainer"
                property bool centeredWallpaperOnlyWhenLocked: false
                property string wallpaperAnimation: "magic"
                property bool enableWallpaperPreview: false
                property string thumbnailPath: ""
                property bool hideWhenFullscreen: true
                property JsonObject parallax: JsonObject {
                    property bool vertical: false
                    property bool autoVertical: false
                    property bool enableWorkspace: true
                    property real workspaceZoom: 1.0 // Relative to wallpaper size
                    property bool enableSidebar: true
                    property real widgetsFactor: 1.2
                }
            }

            property JsonObject bar: JsonObject {
                property JsonObject autoHide: JsonObject {
                    property bool enable: false
                    property int hoverRegionWidth: 2
                    property bool pushWindows: false
                    // Keep the bar shown while a bar popup (media box, tray
                    // overflow) is open, and dismiss that popup when the pointer
                    // leaves it, so the bar can then hide. Prevents popups being
                    // orphaned above a hidden bar. See issues #30, #31.
                    property bool dismissPopups: true
                    property JsonObject showWhenPressingSuper: JsonObject {
                        property bool enable: true
                        property int delay: 140
                    }
                }
                property bool bottom: false // Instead of top
                property int cornerStyle: 0 // 0: Hug | 1: Float | 2: Plain rectangle | 3: M3
                property bool shadow: false // Soft drop shadow under the bar background
                property string borderless: "pills"
                property string topLeftIcon: "spark" // Options: "distro" or any icon name in ~/.config/quickshell/imi/assets/icons
                property bool showBackground: true
                // Opacity of the bar's background chrome (bar/pill fills, hug
                // corners), 0-1. 1 = fully opaque (unchanged). Multiplies the
                // global appearance.transparency alpha rather than replacing it,
                // so the two compose. Below the compositor's per-namespace
                // ignore_alpha blur threshold it reads as plain transparency.
                property real backgroundOpacity: 1.0
                property bool verbose: true
                property bool vertical: false
                property JsonObject resources: JsonObject {
                    property string style: "filled"
                    property bool showValue: false
                    property bool alwaysShowSwap: false
                    property bool alwaysShowCpu: true
                    property bool alwaysShowCpuTemp: false
                    property bool alwaysShowDisk: false
                    property bool alwaysShowRam: true
                    property bool alwaysShowGpu: false
                    property bool alwaysShowGpuTemp: false
                    property bool alwaysShowVram: false
                    property int memoryWarningThreshold: 95
                    property int swapWarningThreshold: 85
                    property int cpuWarningThreshold: 90
                    property int gpuWarningThreshold: 90
                    property int vramWarningThreshold: 95
                }
                property JsonObject divider: JsonObject {
                    property string style: "rect" // rect - dot - space
                    property int spacing: 20
                }

                property JsonObject layouts: JsonObject {
                    property list<string> leftLayout: ["workspaces"]
                    property list<string> middleLayout: ["clockWidget"]
                    property list<string> rightLayout: ["submapIndicator", "privacyIndicator", "systemIcons"]
                }
                
                property list<string> screenList: [] // List of names, like "eDP-1", find out with 'hyprctl monitors' command
                property JsonObject utilButtons: JsonObject {
                    property bool showScreenSnip: true
                    property bool showColorPicker: false
                    property bool showMicToggle: false
                    property bool showKeyboardToggle: true
                    property bool showWallpaperToggle: false
                    property bool showDarkModeToggle: true
                    property bool showPerformanceProfileToggle: false
                    property bool showScreenRecord: false       
                    property bool isRecording: false
                }

                property JsonObject workspaces: JsonObject {
                    property bool monochromeIcons: true
                    property int shown: 10
                    property bool showAppIcons: true
                    property bool showAllMonitors: true // false = only show workspaces on the current monitor
                    property string indicatorStyle: "dot" // "dot" or "icon"
                    property bool alwaysShowNumbers: false
                    property int showNumberDelay: 300 // milliseconds
                    property list<string> numberMap: ["1", "2"] // Characters to show instead of numbers on workspace indicator
                    property bool useNerdFont: false
                }
                property JsonObject weather: JsonObject {
                    property bool enable: false
                    property bool enableGPS: true // gps based location
                    property string city: "" // When 'enableGPS' is false
                    property bool useUSCS: false // Instead of metric (SI) units
                    property int fetchInterval: 10 // minutes
                    property string provider: "owm" // "owm" (OpenWeatherMap) | "wttr" (wttr.in, keyless)
                    property string apiKey: "" // empty = use the built-in OpenWeatherMap key
                }
                property JsonObject privacyIndicator: JsonObject {
                    property bool enable: true
                    property int pollInterval: 2000 // ms
                    property bool showMic: true
                    property bool showCamera: true
                    property bool showScreencast: true
                    // The ambient RGB sampler (OpenRGB monitor sync) grabs a
                    // frame every poll tick, which would blink the screencast
                    // dot once a second. While it runs, only casts that hold
                    // their state longer than a capture pulse are shown.
                    property bool ignoreAmbientCapture: true
                }
                property JsonObject indicators: JsonObject {
                    property JsonObject notifications: JsonObject {
                        property bool showUnreadCount: false
                    }
                }
                property JsonObject tooltips: JsonObject {
                    property bool clickToShow: false
                }
                property JsonObject media: JsonObject {
                    property string preferredPlayer: ""
                    property bool alwaysVisible: false
                    property bool onlyTitle: false
                    property int maxWidth: 280
                    property int minWidth: 100
                }
            }

            property JsonObject battery: JsonObject {
                property int low: 20
                property int critical: 5
                property int full: 101
                property bool automaticSuspend: true
                property int suspend: 3
            }

            property JsonObject calendar: JsonObject {
                property string locale: "en-GB"
                property int firstDayOfWeek: 1 // 1 = Monday .. 7 = Sunday
                property JsonObject ics: JsonObject {
                    property list<string> files: [] // local .ics paths
                    property list<string> urls: []  // remote ICS URLs
                    property int refreshInterval: 30 // minutes
                }
            }

            property JsonObject conflictKiller: JsonObject {
                property bool autoKillNotificationDaemons: false
                property bool autoKillTrays: false
            }

            property JsonObject crosshair: JsonObject {
                // Valorant crosshair format. Use https://www.vcrdb.net/builder
                property string code: "0;P;d;1;0l;10;0o;2;1b;0"
            }

            property JsonObject dock: JsonObject {
                property bool enable: false
                property bool showBackground: true
                property bool showPinButton: true
                property bool showAppsButton: true
                property bool showMedia: true
                property bool monochromeIcons: true
                property real height: 60
                property real hoverRegionHeight: 2
                property bool pinnedOnStartup: false
                property bool hoverToReveal: true // When false, only reveals on empty workspace
                property list<string> pinnedApps: [ // IDs of pinned entries
                    "org.kde.dolphin", "kitty",]
                property list<string> ignoredAppRegexes: []
            }

            property JsonObject dropShelf: JsonObject {
                property bool dragToBarReveal: true // Dragging files over the bar pops the shelf out
                property bool shakeToSummon: false // Shake the cursor while dragging (BTN_LEFT-gated) to summon
                property real shakeSensitivity: 1.0 // Higher = easier to trigger
                property int autoDismissSeconds: 5 // Close an untouched summoned shelf (0 = never)
                property bool blurBackground: true // Translucent tint; the compositor blurs behind it
                property real backgroundOpacity: 0.5
            }

            property JsonObject interactions: JsonObject {
                property JsonObject scrolling: JsonObject {
                    property bool fasterTouchpadScroll: false // Enable faster scrolling with touchpad
                    property int mouseScrollDeltaThreshold: 120 // delta >= this then it gets detected as mouse scroll rather than touchpad
                    property int mouseScrollFactor: 120
                    property int touchpadScrollFactor: 450
                }
                property JsonObject deadPixelWorkaround: JsonObject { // Hyprland leaves out 1 pixel on the right for interactions
                    property bool enable: false
                }
            }

            property JsonObject language: JsonObject {
                property string ui: "auto" // UI language. "auto" for system locale, or specific language code like "zh_CN", "en_US"
                property JsonObject translator: JsonObject {
                    property string engine: "auto" // Run `trans -list-engines` for available engines. auto should use google
                    property string targetLanguage: "auto" // Run `trans -list-all` for available languages
                    property string sourceLanguage: "auto"
                }
            }

            property JsonObject launcher: JsonObject {
                property list<string> pinnedApps: [ "org.kde.dolphin", "kitty", "cmake-gui"]
            }

            property JsonObject light: JsonObject {
                property JsonObject night: JsonObject {
                    property bool automatic: true
                    property string from: "19:00" // Format: "HH:mm", 24-hour time
                    property string to: "06:30"   // Format: "HH:mm", 24-hour time
                    property int colorTemperature: 5000
                }
                property JsonObject antiFlashbang: JsonObject {
                    property bool enable: false
                }
            }

            property JsonObject lock: JsonObject {
                property bool useHyprlock: false
                property bool launchOnStartup: false
                property bool showWidgets: false
                property bool showMedia: true
                property bool showToolbars: true
                property JsonObject blur: JsonObject {
                    property bool enable: true
                    property real radius: 100
                    property real extraZoom: 1.1
                    property int size: 20
                }
                property bool centerClock: true
                property bool showLockedText: true
                property JsonObject security: JsonObject {
                    property bool unlockKeyring: true
                    property bool requirePasswordToPower: false
                }
                property bool materialShapeChars: true
            }

            property JsonObject media: JsonObject {
                // Attempt to remove dupes (the aggregator playerctl one and browsers' native ones when there's plasma browser integration)
                property bool filterDuplicatePlayers: true
            }

            property JsonObject networking: JsonObject {
                property string userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
                property JsonObject vpn: JsonObject {
                    property bool enable: true
                    property int pollInterval: 5000 // ms
                }
                property JsonObject tailscale: JsonObject {
                    property bool enable: true
                    property int pollInterval: 5000 // ms
                }
            }

            // Keep-awake. autoOnExternalMonitor (ported from end-4/dots-hyprland
            // PR #2109) holds the idle inhibitor while an external monitor is
            // connected; it ORs with the manual "Keep system awake" toggle
            // (services/Idle.qml).
            property JsonObject idleInhibitor: JsonObject {
                property bool autoOnExternalMonitor: false
            }

            // OLED screensaver. The idle trigger lives in hypridle.conf (keep its
            // listener timeout in sync); show() no-ops unless enable is true.
            property JsonObject screensaver: JsonObject {
                property bool enable: false
                property string mode: "black" // "black" | "clock"
                property int timeout: 240 // seconds (mirror in hypridle.conf; must be < lock timeout)
            }

            property JsonObject notes: JsonObject {
                // Set once services/Notes.qml has folded the old desktop-notes
                // store (Directories.desktopNotesPath, the array the deleted
                // built-in notes widget wrote) into the live note array.
                //
                // That file is deliberately left on disk, so without a marker
                // every launch would re-import it and any note the user deleted
                // would come back. The plaintext-scratchpad half of the
                // migration needs no marker: it is driven by the shape of the
                // live store, which stops being plaintext the moment it is
                // converted.
                property bool importedLegacyStore: false
            }

            property JsonObject notifications: JsonObject {
                property int timeout: 7000
                property string position: "top_right"
            }

            property JsonObject osd: JsonObject {
                property int timeout: 1000
                property bool lockKeys: true // Caps/Num Lock OSD (polls hyprctl; disable to stop polling)
            }

            property JsonObject osk: JsonObject {
                property string layout: "qwerty_full"
                property bool pinnedOnStartup: false
            }

            property JsonObject overlay: JsonObject {
                property bool openingZoomAnimation: true
                property bool darkenScreen: true
                property real clickthroughOpacity: 0.8
                property JsonObject floatingImage: JsonObject {
                    property string imageSource: "https://media.tenor.com/H5U5bJzj3oAAAAAi/kukuru.gif"
                    property real scale: 0.5
                }
            }

            property JsonObject overview: JsonObject {
                property bool enable: true
                property string style: "default"
                property real scale: 0.18 // Relative to screen size
                property real rows: 2
                property real columns: 5
                property bool orderRightLeft: false
                property bool orderBottomUp: false
                property bool centerIcons: true
            }

            property JsonObject regionSelector: JsonObject {
                property JsonObject targetRegions: JsonObject {
                    property bool windows: true
                    property bool layers: false
                    property bool content: true
                    property bool showLabel: false
                    property real opacity: 0.3
                    property real contentRegionOpacity: 0.8
                    property int selectionPadding: 5
                }
                property JsonObject rect: JsonObject {
                    property bool showAimLines: true
                }
                property JsonObject circle: JsonObject {
                    property int strokeWidth: 6
                    property int padding: 10
                }
                property JsonObject annotation: JsonObject {
                    property bool useSatty: false
                }
            }

            property JsonObject resources: JsonObject {
                property int updateInterval: 3000
                property int historyLength: 60
            }

            property JsonObject tray: JsonObject {
                property bool monochromeIcons: true
                property bool showItemId: false
                property bool invertPinnedItems: true // Makes the below a whitelist for the tray and blacklist for the pinned area
                property list<var> pinnedItems: [ "Fcitx" ]
                property bool filterPassive: true
            }

            property JsonObject musicRecognition: JsonObject {
                property int timeout: 16
                property int interval: 4
            }

            property JsonObject search: JsonObject {
                property int nonAppResultDelay: 30 // This prevents lagging when typing
                property string engineBaseUrl: "https://www.google.com/search?q="
                property list<string> excludedSites: ["quora.com", "facebook.com"]
                property bool sloppy: false // Uses levenshtein distance based scoring instead of fuzzy sort. Very weird.
                property JsonObject prefix: JsonObject {
                    property bool showDefaultActionsWithoutPrefix: true
                    property string action: "/"
                    property string app: ">"
                    property string clipboard: ";"
                    property string emojis: ":"
                    property string keybinds: "<"
                    property string symbols: "."
                    property string math: "="
                    property string shellCommand: "$"
                    property string webSearch: "?"
                    property string file: "~" // File/folder search
                }
                property JsonObject fileSearch: JsonObject {
                    property bool enable: true
                    property string root: "" // empty = $HOME
                    property int maxResults: 20
                    property int delay: 150 // ms debounce
                }
                property JsonObject imageSearch: JsonObject {
                    property string imageSearchEngineBaseUrl: "https://lens.google.com/uploadbyurl?url="
                    property bool useCircleSelection: false
                }
            }

            property JsonObject sidebar: JsonObject {
                property bool banner: false
                property bool mediaPlayer: false
                property string bannerImage: ""
                property bool keepRightSidebarLoaded: true
                property JsonObject translator: JsonObject {
                    property bool enable: false
                    property int delay: 300 // Delay before sending request. Reduces (potential) rate limits and lag.
                }
                property JsonObject media: JsonObject {
                    property bool enable: true
                    property bool artColors: false
                }
                
                property JsonObject ai: JsonObject {
                    property bool textFadeIn: false
                }
                property JsonObject booru: JsonObject {
                    property bool allowNsfw: false
                    property string defaultProvider: "yandere"
                    property int limit: 20
                    property JsonObject zerochan: JsonObject {
                        property string username: "[unset]"
                    }
                }
                property JsonObject cornerOpen: JsonObject {
                    property bool enable: true
                    property bool bottom: false
                    property bool valueScroll: true
                    property bool clickless: false
                    property int cornerRegionWidth: 250
                    property int cornerRegionHeight: 5
                    property bool visualize: false
                    property bool clicklessCornerEnd: true
                    property int clicklessCornerVerticalOffset: 1
                }

                property JsonObject quickToggles: JsonObject {
                    property string style: "android" // Options: classic, android
                    property JsonObject android: JsonObject {
                        property int columns: 5
                        property list<var> toggles: [
                            { "size": 2, "type": "network" },
                            { "size": 2, "type": "bluetooth"  },
                            { "size": 1, "type": "idleInhibitor" },
                            { "size": 1, "type": "mic" },
                            { "size": 2, "type": "audio" },
                            { "size": 2, "type": "nightLight" }
                        ]
                    }
                }

                property JsonObject quickSliders: JsonObject {
                    property bool enable: false
                    property bool showMic: false
                    property bool showVolume: true
                    property bool showBrightness: true
                }
            }

            property JsonObject custom: JsonObject {
                property string distroIcon: ""
                property bool colorizeIcon: true
            }

            property JsonObject screenRecord: JsonObject {
                property string savePath: Directories.videos.replace("file://","") // strip "file://"
                property int fps: 60
                property string quality: "very_high" // medium | high | very_high | ultra
                property string codec: "auto" // auto | h264 | hevc | av1
                property string audioCodec: "opus" // opus | aac | flac
                property bool recordAudio: true // desktop audio on recordings/replays
                property bool recordMic: false // merge the mic into the audio track
                property bool showCursor: true
                property string framerateMode: "vfr" // cfr | vfr | content
                property JsonObject replay: JsonObject {
                    property bool enable: false // instant-replay ring buffer daemon
                    property int duration: 120 // seconds kept in the buffer
                    property string savePath: "" // "" = screenRecord.savePath
                    property string monitor: "" // "" = whole screen
                    property string storage: "ram" // ram | disk
                    property bool restartOnSave: false // clear the buffer after each save
                }
            }

            property JsonObject screenSnip: JsonObject {
                property string savePath: "" // only copy to clipboard when empty
            }

            property JsonObject screenshotResult: JsonObject {
                property bool enable: true
                property int timeoutMs: 6000
                // Annotation tool override; [] = auto-detect (swappy, then satty).
                property list<string> editorCommand: []
            }

            property JsonObject sounds: JsonObject {
                property bool battery: false
                property bool pomodoro: false
                property string theme: "freedesktop"
            }

            property JsonObject time: JsonObject {
                // https://doc.qt.io/qt-6/qtime.html#toString
                property string format: "hh:mm"
                property string shortDateFormat: "dd/MM"
                property string dateWithYearFormat: "dd/MM/yyyy"
                property string dateFormat: "ddd, dd/MM"
                property JsonObject pomodoro: JsonObject {
                    property int breakTime: 300
                    property int cyclesBeforeLongBreak: 4
                    property int focus: 1500
                    property int longBreak: 900
                }
                property bool secondPrecision: false
            }

            property JsonObject updates: JsonObject {
                property bool enableCheck: true
                property int checkInterval: 120 // minutes
                property int adviseUpdateThreshold: 75 // packages
                property int stronglyAdviseUpdateThreshold: 200 // packages
            }
            
            property JsonObject wallpaperSelector: JsonObject {
                property bool useSystemFileDialog: false
                property bool showBlurBackground: false
                property bool showHomePath: true
                property string userPath: "" // This can be set to any path and it will show up as a quick access in the wallpaper selector"
                property string liveWallpapersPath: ""
                property bool showSearchbar: true
                property int columns: 4
                property bool closeAfterSelection: true
                property int changeInterval: 0 
                property JsonObject wallpaperEngine: JsonObject {
                    property string libraryPath: ""
                    property string activeProject: ""
                    property string activePath: ""
                    property string activePreview: ""
                    // Wallpaper type of the active project (scene/video/web). "web"
                    // is unsupported by the embedded renderer (needs CEF), so the
                    // background falls back to the static wallpaper for it.
                    property string activeType: ""
                    // `activeStill` used to live here: a full-scene still rendered
                    // from the active project. The selector-only refactor removed
                    // the code that generated those stills and wrote the field, but
                    // left the field and its readers, so it sat frozen at whatever
                    // it held that day - and applying a preset restored that stale
                    // value, which is how it spread (#103). Removed rather than
                    // repaired: `activePreview` is maintained by
                    // WallpaperEngine.apply() and always matches the active project.
                    //
                    // Deliberately not migrated away on disk. The JsonAdapter does
                    // not expose keys it has no property for, so the leftover key is
                    // inert - the same treatment the desktop-widget keys got above,
                    // and it keeps a downgrade working.
                    property int fps: 30
                    property string scaling: "fill"
                    property bool silent: true
                }
            }

            property JsonObject windows: JsonObject {
                property bool showTitlebar: true // Client-side decoration for shell apps
                property bool centerTitle: true
            }

            property JsonObject hacks: JsonObject {
                property int arbitraryRaceConditionDelay: 20 // milliseconds
            }

            property JsonObject workSafety: JsonObject {
                property JsonObject enable: JsonObject {
                    property bool wallpaper: false
                    property bool clipboard: false
                }
                property JsonObject triggerCondition: JsonObject {
                    property list<string> networkNameKeywords: ["airport", "cafe", "college", "company", "eduroam", "free", "guest", "public", "school", "university"]
                    property list<string> fileKeywords: ["anime", "booru", "ecchi", "hentai", "yande.re", "konachan", "breast", "nipples", "pussy", "nsfw", "spoiler", "girl"]
                    property list<string> linkKeywords: ["hentai", "porn", "sukebei", "hitomi.la", "rule34", "gelbooru", "fanbox", "dlsite"]
                }
            }
        }
    }
}
