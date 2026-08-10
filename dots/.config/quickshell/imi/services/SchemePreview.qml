pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Per-scheme swatches for the scheme pickers, computed from the current
 * wallpaper (one quantize, every variant) in the color venv.
 *
 * `swatches` is scheme value -> [primary, secondary, tertiary] hex strings,
 * exactly what scripts/colors/scheme_preview.py prints, plus the "auto" entry
 * it derives. Empty until a run succeeds, so every consumer needs a fallback.
 *
 * This lived inside the settings page and now has a second reader in the
 * desktop menu's Wallpaper & style submenu (#142) - a surface that is created
 * and destroyed on every hover, so re-running a wallpaper quantize per open was
 * not an option. The result is therefore cached against the inputs that produce
 * it and `refresh()` is a no-op while they are unchanged: a consumer coming on
 * screen calls it unconditionally and pays nothing when the cache is warm.
 * Nothing is recomputed while no consumer is showing.
 */
Singleton {
    id: root

    property var swatches: ({})

    readonly property string sourcePath: /\.(mp4|webm|mkv|avi|mov)$/i.test(WallpaperEngine.activeArtwork)
        ? Config.options.background.thumbnailPath
        : WallpaperEngine.activeArtwork
    readonly property string mode: Appearance.m3colors.darkmode ? "dark" : "light"
    // What a cached result belongs to. A consumer observes this and calls
    // refresh() when it changes; the guard inside makes that free.
    readonly property string inputs: root.sourcePath + "|" + root.mode

    property string cachedInputs: ""

    function refresh(): void {
        if (root.sourcePath.length === 0 || root.inputs === root.cachedInputs)
            return
        previewDebounce.restart()
    }

    Timer {
        // A wallpaper switch changes the source and the dark/light mode
        // together, so an undebounced refresh spawns the venv twice for one
        // event. The key is stamped here rather than in refresh(), so an input
        // that changes again inside the window is still the one that runs.
        id: previewDebounce
        interval: 200
        onTriggered: {
            root.cachedInputs = root.inputs
            previewProcess.running = false
            previewProcess.running = true
        }
    }

    Process {
        id: previewProcess
        command: ["bash", "-c",
            // The \${...} escape stops QML's own template substitution from
            // eating bash's parameter expansion.
            `source "\${IMMATERIAL_IMPULSE_VIRTUAL_ENV:-$ILLOGICAL_IMPULSE_VIRTUAL_ENV}/bin/activate" && ` +
            `python3 '${Directories.scriptPath}/colors/scheme_preview.py' ` +
            `--path '${StringUtils.shellSingleQuoteEscape(root.sourcePath)}' ` +
            `--mode ${root.mode}`]
        stdout: StdioCollector {
            id: previewCollector
            onStreamFinished: {
                let parsed = null
                try {
                    parsed = JSON.parse(previewCollector.text)
                } catch (error) {
                    parsed = null
                }
                if (!parsed || parsed.error) {
                    // Clear the key rather than the swatches: the last good
                    // palette is still a better preview than none, and the next
                    // refresh() should retry instead of trusting a failed run.
                    root.cachedInputs = ""
                    return
                }
                root.swatches = parsed
            }
        }
    }
}
