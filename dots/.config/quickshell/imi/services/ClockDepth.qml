pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick
import "../modules/common/functions/clockDepth.js" as ClockDepthLogic

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
    // The desktop selector counts as picking for every purpose here, and it is
    // read off the flag rather than given a `picking` write of its own: the
    // picker is destroyed as the wallpaper selector closes and the mode arms,
    // so one bool with two writers would be cleared by the surface that is
    // going away, on an ordering nothing here controls - and clearing it
    // forgets the candidate the user is about to judge.
    readonly property bool watching: root.enabled || root.picking
        || GlobalStates.clockDepthSelectOpen

    // A live Wallpaper Engine project, as the config names it. Case-insensitive
    // on the type because the scanner emits "Web"; a web project falls back to
    // the static wallpaper and is that wallpaper's question, not this one.
    readonly property string weProject: Config.options.wallpaperSelector.wallpaperEngine.activeProject ?? ""
    readonly property bool weActive: root.weProject !== ""
        && (Config.options.wallpaperSelector.wallpaperEngine.activePath ?? "") !== ""
        && (Config.options.wallpaperSelector.wallpaperEngine.activeType ?? "").toLowerCase() !== "web"
    // The project has no file to segment; the shell photographs it (spec §8.1,
    // Background.captureGreeterStill) and that still is the picture. The path
    // is derived from the project the config already names, never stored -
    // see the note where `activeStill` used to be declared in Config.qml.
    readonly property string weStillPath: root.weProject === "" ? ""
        : `${Directories.wallpaperEngineStills}/${root.weProject}.png`
    // Whether the question on the table is the project's. A preview always wins
    // - the selector is showing a still picture over the live scene and the
    // picker beside it is about THAT picture - and outside a preview it is the
    // project's exactly when the project is what the desktop draws.
    readonly property bool askingWe: Wallpapers.previewPath === "" && root.weActive
    // The producer keys a project's cache on this rather than on the still's
    // stat triple, which moves every session (spec §8.2).
    readonly property string identity: root.askingWe ? `we:${root.weProject}` : ""
    // The wallpaper on screen, not the one in the config: the selector previews
    // by path while the user arrows through the grid, and a mask belonging to
    // the previous wallpaper drawn over this one is a silhouette in the wrong
    // place rather than a missing effect.
    readonly property string wallpaperPath: root.askingWe ? root.weStillPath
        : (Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath)
    // False only for a project whose still has not been grabbed yet - the one
    // query that can be answered before its picture exists. Reported by the
    // producer's status, so the shell never stats the file itself.
    property bool stillAvailable: true

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
    // Cache-busting tokens for the mask files, owned by the producer like the
    // key. Qt caches a pixmap by URL and both of these files are rewritten in
    // place - the candidate on every click, the accepted mask when a second
    // candidate is accepted for the same wallpaper - so without them the
    // picture on screen is whichever mask happened to load first.
    property string maskRevision: ""
    property var revisions: ({})

    readonly property bool optedOut: root.state === "declined"

    // Whether the desktop is currently showing the still image this service is
    // asking about, which is the precondition for picking a subject on it.
    // Assembled here because two windows read it - the picker's way in, and the
    // selection mode's own guard against the ground moving under it - and two
    // copies of a predicate are two answers waiting to disagree.
    readonly property bool selectable: ClockDepthLogic.selectable({
        wallpaperPath: root.wallpaperPath,
        previewing: Wallpapers.previewPath !== "",
        weActive: root.weActive,
        maskIsWe: root.askingWe,
        stillMissing: root.askingWe && !root.stillAvailable,
        centeredWallpaper: Config.options.background.centeredWallpaper ?? false,
        screenLocked: GlobalStates.screenLocked
    })

    property string queriedPath: ""

    // The picker's side. Everything below is reached only from a button.
    //
    // The producer names the models and says what each is asked with, so the
    // picker does not carry a second copy of the list. This is the value it
    // answers with today, kept only so the picker's columns are drawn on the
    // frame it opens rather than 200ms later - `tests/test_clock_depth_models.py`
    // fails the suite when it stops matching what the producer reports.
    property var modelSpecs: [
        { "name": "isnet-anime", "kind": "salient" },
        { "name": "isnet-general-use", "kind": "salient" },
        { "name": "mobile-sam", "kind": "prompted" }
    ]
    // "" while nothing is running, otherwise the model being segmented. The
    // picker disables itself on this rather than on a bare boolean, so it can
    // say WHICH model is running - a run is 1.3 to 4.5 seconds and a button that
    // only greys out reads as a hang.
    property string running: ""
    property string lastError: ""

    // The clicks the prompted column is working from, in the picture's own
    // normalised frame. One list rather than one per model because there is one
    // prompted model; the producer refuses the verb for the others.
    property var points: []
    // Restoration is keyed on the wallpaper rather than done on every status,
    // because a click that finds nothing writes no candidate - so re-reading the
    // prompt off the cache after one would silently discard the click the user
    // just made, along with any way to undo or refine it.
    property string promptRestoredFor: ""
    // A click that arrived while the previous one was still decoding. Dropping
    // it would be the natural thing and the wrong one: the whole gesture is
    // adding points, and at ~0.3s per decode a user placing three of them
    // outruns it.
    property bool selectPending: false

    readonly property string promptedModel: {
        for (const spec of root.modelSpecs) {
            if (spec.kind === "prompted")
                return spec.name
        }
        return ""
    }
    // What the prompted column was cut with, whether or not it is the one the
    // desktop draws. The picker shows these back so re-opening on a wallpaper
    // is the gesture continued rather than an unexplained cutout.
    property var prompts: ({})
    property var acceptedPrompt: []

    function looksLikeList(value): bool {
        return value !== null && value !== undefined && typeof value.length === "number"
    }

    // History keeps whole point lists rather than a stack of "remove the last
    // click", so that start-over is one undo away like every other step. A
    // pop-the-last-point stack cannot express it: clearing four points would
    // cost four undos or be silently unrecoverable, and both read as the
    // history having lost the gesture.
    property var pointHistory: []
    property var pointFuture: []

    // Every deliberate edit goes through here, so no path can move the points
    // without the history seeing it.
    function commitPoints(next): void {
        root.pointHistory = root.pointHistory.concat([root.points])
        root.pointFuture = []
        root.points = next
        root.selectPoints()
    }

    // Adopting a prompt off disk is where a gesture starts, not a step in one,
    // so it resets the history instead of becoming undoable into someone
    // else's clicks.
    function adoptPoints(next): void {
        root.pointHistory = []
        root.pointFuture = []
        root.points = next
    }

    function addPoint(x: real, y: real, include: bool): void {
        if (root.promptedModel === "")
            return
        root.commitPoints(root.points.concat([{ "x": x, "y": y, "label": include ? 1 : 0 }]))
    }

    function undoPoint(): void {
        if (root.pointHistory.length === 0)
            return
        root.pointFuture = root.pointFuture.concat([root.points])
        root.points = root.pointHistory[root.pointHistory.length - 1]
        root.pointHistory = root.pointHistory.slice(0, root.pointHistory.length - 1)
        root.selectPoints()
    }

    function redoPoint(): void {
        if (root.pointFuture.length === 0)
            return
        root.pointHistory = root.pointHistory.concat([root.points])
        root.points = root.pointFuture[root.pointFuture.length - 1]
        root.pointFuture = root.pointFuture.slice(0, root.pointFuture.length - 1)
        root.selectPoints()
    }

    function clearPoints(): void {
        if (root.points.length === 0)
            return
        root.commitPoints([])
    }

    function selectPoints(): void {
        if (root.wallpaperPath === "" || root.promptedModel === "")
            return
        if (root.running !== "") {
            root.selectPending = true
            return
        }
        root.lastError = ""
        root.selectPending = false
        root.running = root.promptedModel
        const args = root.points.map(point =>
            `--point ${point.x.toFixed(4)},${point.y.toFixed(4)},${point.label}`).join(" ")
        selectProcess.command = ["bash", "-c",
            `source "\${IMMATERIAL_IMPULSE_VIRTUAL_ENV:-$ILLOGICAL_IMPULSE_VIRTUAL_ENV}/bin/activate" && ` +
            `python3 '${Directories.scriptPath}/background/subject_mask.py' select ` +
            `'${StringUtils.shellSingleQuoteEscape(root.wallpaperPath)}' ` +
            `--model ${root.promptedModel} ${args}${root.identityArg()}`]
        selectProcess.running = true
    }

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
            `'${StringUtils.shellSingleQuoteEscape(root.wallpaperPath)}' --model ${model}${root.identityArg()}`]
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
            .concat(root.identity === "" ? [] : ["--identity", root.identity])
        verdictProcess.running = true
    }

    // The identity as a shell argument, for the two verbs that go through
    // bash. A project id is digits, and the prefix is ours, but it is quoted
    // like the path anyway rather than trusted.
    function identityArg(): string {
        return root.identity === "" ? ""
            : ` --identity '${StringUtils.shellSingleQuoteEscape(root.identity)}'`
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
        root.stillAvailable = true
        root.key = ""
        root.maskPath = ""
        root.candidates = ({})
        root.acceptedModel = ""
        root.maskRevision = ""
        root.revisions = ({})
        root.queriedPath = ""
        root.prompts = ({})
        root.acceptedPrompt = []
        root.adoptPoints([])
        root.promptRestoredFor = ""
        root.selectPending = false
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
            "status", root.queriedPath].concat(root.identity === "" ? [] : ["--identity", root.identity])
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
                    root.maskRevision = ""
                    root.revisions = ({})
                    return
                }
                root.state = parsed.state ?? "error"
                root.key = parsed.key ?? ""
                root.stillAvailable = parsed.available ?? true
                root.maskPath = parsed.state === "accepted" ? (parsed.mask ?? "") : ""
                root.candidates = parsed.candidates ?? ({})
                root.acceptedModel = parsed.acceptedModel ?? ""
                root.maskRevision = parsed.maskRevision ?? ""
                root.revisions = parsed.revisions ?? ({})
                root.prompts = parsed.prompts ?? ({})
                root.acceptedPrompt = parsed.acceptedPrompt ?? []
                // Array-LIKENESS rather than Array.isArray, here and below: a
                // list that has been through a `property var` is a QVariantList
                // on the way back and keeps its indices and its length while
                // losing the brand, which is the same trap a manifest's
                // grid.sizes hit crossing a model boundary.
                if (root.looksLikeList(parsed.models) && parsed.models.length > 0)
                    root.modelSpecs = parsed.models
                if (root.promptRestoredFor !== root.queriedPath) {
                    root.promptRestoredFor = root.queriedPath
                    // The candidate's clicks first: that is the working state,
                    // and it exists whenever the user has clicked at all. The
                    // accepted mask's are the fallback, so re-opening on a
                    // wallpaper whose cutout was kept shows the gesture that
                    // produced what is on screen rather than an empty preview
                    // with no way back into it.
                    const candidate = root.prompts?.[root.promptedModel]
                    root.adoptPoints(root.looksLikeList(candidate) ? candidate
                        : (root.looksLikeList(root.acceptedPrompt) ? root.acceptedPrompt : []))
                }
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
        id: selectProcess
        stdout: StdioCollector {
            id: selectCollector
            onStreamFinished: {
                root.running = ""
                let parsed = null
                try {
                    parsed = JSON.parse(selectCollector.text)
                } catch (error) {
                    parsed = null
                }
                if (!parsed || parsed.state === "error") {
                    root.lastError = parsed?.error
                        ?? Translation.tr("Could not cut a mask from those points.")
                    root.selectPending = false
                    return
                }
                if (parsed.state === "empty")
                    root.lastError = Translation.tr(
                        "Nothing there. Click on the subject itself, or right-click to exclude what it grabbed.")
                // Same discipline as a run: the select wrote a candidate or
                // removed one, and `status` is what turns either into what the
                // picker draws - so the answer comes back through the one
                // reader rather than being mirrored into a second notion of it.
                root.refresh()
                if (root.selectPending)
                    root.selectPoints()
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
