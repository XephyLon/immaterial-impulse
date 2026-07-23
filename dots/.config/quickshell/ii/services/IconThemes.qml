pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

// Enumerates installed icon themes (via scripts/icons/scan-icon-themes.py) and
// exposes them for the icon-pack selector. Detection lives in the python scanner
// so it is unit-testable; this singleton just runs it and parses the JSON.
Singleton {
    id: root

    property var themes: []
    property bool loading: false
    readonly property bool available: themes.length > 0

    // The theme the shell/system is currently set to. The config override wins;
    // when it is empty we fall back to the live gsettings value (probed below) so
    // the grid can still mark the active card.
    property string systemIconTheme: ""
    readonly property string activeId: Config.options.appearance.iconTheme || root.systemIconTheme

    signal refreshed()

    function load() {
        if (scanProcess.running) return;
        root.loading = true;
        scanProcess.command = ["python3", Directories.iconThemeScanScriptPath];
        scanProcess.running = true;
        if (!systemThemeProbe.running) systemThemeProbe.running = true;
    }

    // Apply a theme by id: run the system-wide apply script, then (on success)
    // record it in config and relaunch the shell so its own icons update. The id
    // is validated again inside the script; here we only pass known ids from the
    // scanned list.
    function apply(themeId) {
        if (applyProcess.running) return;
        applyProcess.pendingId = themeId;
        applyProcess.command = [Directories.iconThemeApplyScriptPath, themeId];
        applyProcess.running = true;
    }

    // Probe the live system icon theme so activeId can mark the current pack even
    // before the user picks one through this selector (config override empty).
    Process {
        id: systemThemeProbe
        command: ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.systemIconTheme = text.trim().replace(/^'|'$/g, "");
            }
        }
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
        property string pendingId: ""
        onExited: exitCode => {
            if (exitCode === 0) {
                Config.options.appearance.iconTheme = applyProcess.pendingId;
                // The shell's Qt icon theme is fixed at process launch, so a QML
                // reload will not adopt it - relaunch the process. Double-forked
                // via execDetached so it outlives the shell it kills.
                Quickshell.execDetached(["bash", "-c",
                    "sleep 0.3; qs kill >/dev/null 2>&1; qs -c ii -d >/dev/null 2>&1 &"]);
            }
            applyProcess.pendingId = "";
        }
    }

    Component.onCompleted: root.load()
}
