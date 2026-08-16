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
 * spawn and never reaches ONNX Runtime. `runModel` is the only thing that loads
 * one, it costs seconds and a gigabyte, and it is reachable only from the
 * wallpaper selector's picker - nothing reactive here can start a run.
 *
 * Nothing runs at all until either `background.clockDepth.enable` (default
 * false) or the picker is open, so a machine that has never used depth pays
 * nothing for it, and neither does a wallpaper that has no mask once it is on.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options.background.clockDepth?.enable ?? false
    // Set by the picker while it is on screen. The cache is queried while EITHER
    // this or the global switch is on: with only the switch, opening the picker
    // on a machine that has never enabled depth would show nothing and be unable
    // to accept anything - which is the one order every new user arrives in.
    property bool picking: false
    readonly property bool watching: root.enabled || root.picking

    // The wallpaper on screen, not the one in the config: the selector previews
    // by path while the user arrows through the grid, and a mask belonging to
    // the previous wallpaper drawn over this one is a silhouette in the wrong
    // place rather than a missing effect.
    readonly property string wallpaperPath:
        Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath

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
    // Which model's candidate the accepted mask is a copy of; "" when nothing
    // is accepted, and also when it matches neither, because re-running a model
    // overwrites its candidate. Derived by the producer from the bytes rather
    // than recorded anywhere, so it cannot drift from the file the shell draws.
    property string acceptedModel: ""

    readonly property bool optedOut: root.state === "declined"

    property string queriedPath: ""

    // The picker's side. Everything below is reached only from a button.
    readonly property list<string> models: ["isnet-anime", "isnet-general-use"]
    // "" while nothing is running, otherwise the model being segmented. The
    // picker disables itself on this rather than on a bare boolean, so it can
    // say WHICH model is running - a run is 1.3 to 4.5 seconds and a button that
    // only greys out reads as a hang.
    property string running: ""
    property string lastError: ""

    // Deliberately not driven by anything reactive. Segmentation costs ~1GB of
    // transient RSS and produces an unusable mask about a third of the time, so
    // it is a user action and can only ever be one; nothing observes a wallpaper
    // change and starts one.
    function runModel(model: string): void {
        if (root.running !== "" || root.wallpaperPath === "")
            return
        root.lastError = ""
        root.running = model
        maskProcess.command = ["bash", "-c",
            `source "\${IMMATERIAL_IMPULSE_VIRTUAL_ENV:-$ILLOGICAL_IMPULSE_VIRTUAL_ENV}/bin/activate" && ` +
            `python3 '${Directories.scriptPath}/background/subject_mask.py' run ` +
            `'${StringUtils.shellSingleQuoteEscape(root.wallpaperPath)}' --model ${model}`]
        maskProcess.running = true
    }

    function acceptModel(model: string): void {
        root.verdict(["accept", "--model", model])
    }

    function declineWallpaper(): void {
        root.verdict(["decline"])
    }

    function verdict(args: list<string>): void {
        if (root.wallpaperPath === "")
            return
        // python3 rather than the venv: both verdicts only move files around,
        // and a venv that has not been built must not be what stops the user
        // saying no to a mask.
        verdictProcess.command = ["python3",
            `${Directories.scriptPath}/background/subject_mask.py`,
            args[0], root.wallpaperPath].concat(args.slice(1))
        verdictProcess.running = true
    }

    function refresh(): void {
        // Unconditional by design, and cheap because of it: the picker pokes
        // this after an accept or a decline, where the path has not changed but
        // the answer has.
        root.queriedPath = ""
        queryDebounce.restart()
    }

    function forget(): void {
        root.state = ""
        root.key = ""
        root.maskPath = ""
        root.candidates = ({})
        root.acceptedModel = ""
        root.queriedPath = ""
    }

    onWallpaperPathChanged: {
        // Both halves matter. A new wallpaper has a different key, so every
        // cached answer here is about the wrong picture until the next query
        // says otherwise - and clearing rather than keeping means the moment
        // between the two draws nothing instead of the previous subject.
        root.forget()
        queryDebounce.restart()
    }

    onWatchingChanged: {
        if (root.watching)
            queryDebounce.restart()
        else
            root.forget()
    }

    Timer {
        // Arrowing through the wallpaper grid changes the preview path per
        // keystroke. The path is stamped when the timer fires rather than when
        // it is armed, so a path that changes again inside the window is still
        // the one that gets asked about.
        id: queryDebounce
        interval: 200
        onTriggered: {
            if (!root.watching || root.wallpaperPath === ""
                || root.wallpaperPath === root.queriedPath)
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
                    root.acceptedModel = ""
                    return
                }
                root.state = parsed.state ?? "error"
                root.key = parsed.key ?? ""
                root.maskPath = parsed.state === "accepted" ? (parsed.mask ?? "") : ""
                root.candidates = parsed.candidates ?? ({})
                root.acceptedModel = parsed.acceptedModel ?? ""
            }
        }
    }

    Process {
        id: maskProcess
        stdout: StdioCollector {
            id: maskCollector
            onStreamFinished: {
                root.running = ""
                let parsed = null
                try {
                    parsed = JSON.parse(maskCollector.text)
                } catch (error) {
                    parsed = null
                }
                if (!parsed || parsed.state === "error") {
                    root.lastError = parsed?.error
                        ?? Translation.tr("Could not run the segmentation model.")
                    return
                }
                // The run wrote a candidate or a refusal marker; `status` is
                // what turns either into what the picker draws, so the answer
                // comes back through the one reader rather than being mirrored
                // here into a second notion of the same state.
                root.refresh()
            }
        }
    }

    Process {
        id: verdictProcess
        stdout: StdioCollector {
            id: verdictCollector
            onStreamFinished: {
                let parsed = null
                try {
                    parsed = JSON.parse(verdictCollector.text)
                } catch (error) {
                    parsed = null
                }
                if (!parsed || parsed.state === "error")
                    root.lastError = parsed?.error
                        ?? Translation.tr("Could not record that choice.")
                root.refresh()
            }
        }
    }
}
