pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

// Enumerates installed cursor themes (via scripts/cursor/scan-cursor-themes.py)
// and applies one (via scripts/cursor/apply-cursor-theme.sh) for the Cursor
// settings page. Detection lives in the python scanner so it is unit-testable;
// this singleton just runs it and parses the JSON, mirroring IconThemes.
Singleton {
    id: root

    property var themes: []
    property bool loading: false
    readonly property bool available: themes.length > 0

    // The config default matches the theme the dots have always shipped and
    // set at startup (execs.lua), so no live probe is needed to mark the
    // active theme before the user first picks one here.
    readonly property string activeId: Config.options.hyprland.cursor.theme

    signal refreshed()

    function load() {
        if (scanProcess.running) return;
        root.loading = true;
        scanProcess.command = ["python3", Directories.cursorThemeScanScriptPath];
        scanProcess.running = true;
    }

    // Theme and size apply together: hyprctl setcursor takes both, and GTK
    // stores them as two keys of one choice. The values are validated again
    // inside the script; config is recorded only on success, so a failed
    // apply cannot persist a theme or size the system never adopted.
    function apply(themeId, size) {
        if (applyProcess.running) return;
        applyProcess.pendingTheme = themeId;
        applyProcess.pendingSize = size;
        applyProcess.command = [Directories.cursorThemeApplyScriptPath, themeId, String(size)];
        applyProcess.running = true;
    }

    Process {
        id: scanProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.themes = Array.isArray(parsed) ? parsed : [];
                } catch (e) {
                    root.themes = [];
                }
            }
        }
        onExited: exitCode => {
            root.loading = false;
            root.refreshed();
        }
    }

    Process {
        id: applyProcess
        property string pendingTheme: ""
        property int pendingSize: 24
        onExited: exitCode => {
            if (exitCode === 0) {
                Config.options.hyprland.cursor.theme = applyProcess.pendingTheme;
                Config.options.hyprland.cursor.size = applyProcess.pendingSize;
            }
            applyProcess.pendingTheme = "";
        }
    }

    Component.onCompleted: root.load()
}
