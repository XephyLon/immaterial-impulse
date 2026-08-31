//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1
import "modules/common"
import "services"
import "panelFamilies"
import qs.modules.common.plugins
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    ReloadPopup {}

    // Always-on host for plugin `panel` entry points; also keeps the
    // ScreenshotEvents IPC handler alive.
    PluginPanelHost {}

    // Keep the recorder service alive: its replay daemon, IPC handler and
    // global shortcuts must exist even before any UI references it.
    readonly property var _screenRecord: ScreenRecord

    Process {
        id: autostartProc
        command: ["python3", `${Directories.scriptPath}/hyprland/autostart.py`]
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return


            if (Config.options.hyprland.autostartApps.enable &&
                Config.options.hyprland.autostartApps.apps.length > 0) {
                autostartProc.running = true
            }
        }
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        Idle.load() // so auto keep-awake on external monitors runs without any UI touching Idle
        AutoTheme.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        // The tray watchdog (scripts/tray/sni_watchdog.py): keeps a
        // persistent SNI watcher alive and resurrects Electron items after
        // a watcher flap - see the script's header. flock-guarded, so
        // shell restarts never stack copies.
        Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/tray/sni_watchdog.py")])
        Cliphist.refresh()
        Wallpapers.load()
        WallpaperEngine.load()
        Updates.load()
        OpenRgb.load()
        PopupBlurThreshold.load() // writes the popup blur threshold rules.lua reads
        LyricsService.restartLyrics()
    }
    
    PanelFamilyLoader {
        identifier: "imi"
        component: ImmaterialImpulseFamily {}
    }

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        // "ii" is what configs written before the rename hold; "waffle" is
        // end-4's second family, which was never ported here. Config's upstream
        // key migration rewrites both, but this stays as the backstop, because
        // what it prevents is a completely blank desktop with no error anywhere
        // - too costly to make conditional on a write having landed.
        readonly property var legacyFamilies: ["ii", "waffle"]
        readonly property string selected: legacyFamilies.includes(Config.options.panelFamily) ? "imi" : Config.options.panelFamily
        active: Config.ready && selected === identifier
    }
}
