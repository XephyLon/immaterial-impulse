pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * What the subject-mask cache holds for the wallpaper that is on screen.
 *
 * The shell never computes a cache key. scripts/background/subject_mask.py owns
 * the derivation (path, mtime and size) and this asks it; a second
 * implementation in QML would be two things that must agree, with nothing
 * reporting it when they stop - which is the `activeStill` shape.
 *
 * `status` is stdlib-only and loads no model, so a query costs a ~35ms process
 * spawn and never reaches ONNX Runtime. Segmentation is only ever reached from
 * an explicit user action; nothing here can start one.
 *
 * Nothing runs at all while `background.clockDepth.enable` is false, which is
 * the default - so a machine that has never turned the feature on pays nothing
 * for it, and neither does a wallpaper that has no mask once it is on.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options.background.clockDepth?.enable ?? false

    // The wallpaper on screen, not the one in the config: the selector previews
    // by path while the user arrows through the grid, and a mask belonging to
    // the previous wallpaper drawn over this one is a silhouette in the wrong
    // place rather than a missing effect.
    readonly property string wallpaperPath: root.enabled
        ? (Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath)
        : ""

    // One of: "" (nothing asked yet), "absent", "candidate", "none",
    // "accepted", "declined", "unreadable", "error".
    property string state: ""
    property string key: ""
    // Only ever set for "accepted". The shell draws this file and no other -
    // a candidate is something the picker offers, not something the desktop
    // shows.
    property string maskPath: ""
    // model name -> candidate mask path, or null where that model looked and
    // found nothing. The picker reads this; the depth layer does not.
    property var candidates: ({})

    readonly property bool optedOut: root.state === "declined"

    property string queriedPath: ""

    function refresh(): void {
        // Unconditional by design, and cheap because of it: the picker pokes
        // this after an accept or a decline, where the path has not changed but
        // the answer has.
        root.queriedPath = ""
        queryDebounce.restart()
    }

    onWallpaperPathChanged: {
        if (root.wallpaperPath === "") {
            root.state = ""
            root.key = ""
            root.maskPath = ""
            root.candidates = ({})
            return
        }
        queryDebounce.restart()
    }

    Timer {
        // Arrowing through the wallpaper grid changes the preview path per
        // keystroke. The path is stamped when the timer fires rather than when
        // it is armed, so a path that changes again inside the window is still
        // the one that gets asked about.
        id: queryDebounce
        interval: 200
        onTriggered: {
            if (root.wallpaperPath === "" || root.wallpaperPath === root.queriedPath)
                return
            root.queriedPath = root.wallpaperPath
            statusProcess.running = false
            statusProcess.running = true
        }
    }

    Process {
        id: statusProcess
        // python3, not the venv wrapper: `status` imports nothing outside the
        // standard library, and routing it through the venv would make the
        // shell's read path fail on a machine whose venv has not been built -
        // silently, and identically to a wallpaper that has no mask.
        command: ["python3", `${Directories.scriptPath}/background/subject_mask.py`,
            "status", root.queriedPath]
        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: {
                let parsed = null
                try {
                    parsed = JSON.parse(statusCollector.text)
                } catch (error) {
                    parsed = null
                }
                if (!parsed) {
                    // Keep the key clear so the next refresh retries rather
                    // than trusting a run that produced nothing parseable.
                    root.queriedPath = ""
                    root.state = "error"
                    root.maskPath = ""
                    root.candidates = ({})
                    return
                }
                root.state = parsed.state ?? "error"
                root.key = parsed.key ?? ""
                root.maskPath = parsed.state === "accepted" ? (parsed.mask ?? "") : ""
                root.candidates = parsed.candidates ?? ({})
            }
        }
    }
}
