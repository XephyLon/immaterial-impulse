pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "frecency.js" as Frecency

/**
 * Launch history, so the launcher can offer the app the user actually opens.
 *
 * `services/AppSearch.qml` ranked on textual match alone, which is why typing
 * three letters kept offering the same wrong app however many times the right
 * one was picked instead. This is the other half of that ordering: how often
 * an app is launched and how recently, folded into one number by
 * `frecency.js`, which owns all of the arithmetic and none of the file.
 *
 * Separate from `services/DockLaunchTracker.qml` on purpose, and it stays
 * separate. That one is ephemeral by design - a ten-second window between a
 * click and a window mapping, plus a per-session "has this icon appeared yet"
 * registry it deliberately prunes when an app leaves the dock. Persisting
 * either would break what they are for: a pending launch must not outlive the
 * process that was waiting for the window, and the dock's appear animation is
 * supposed to play again after a restart. It also keys on the Wayland app_id,
 * while ranking keys on the desktop-entry id the search matches against;
 * writing one store from both without resolving between them would file
 * launches under keys the ranker never looks up. What the two share is the
 * event, so the dock's launch buttons record here as well - through the
 * desktop entry they already hold, which is where the right key comes from.
 *
 * Every launch writes. `FileView.atomicWrites` is what keeps a store that is
 * rewritten this often from ever being read half-written, and the debounce
 * below collapses a double-click into one write rather than two.
 */
Singleton {
    id: root

    readonly property string filePath: Directories.appUsagePath

    // True once the store on disk has been read. Writers are gated on it: a
    // launch recorded before the load lands would serialize the empty startup
    // store over the user's real history.
    property bool ready: false

    property var store: Frecency.emptyStore()

    // Bumped on every mutation. Ranking reads `store` through a plain function
    // call, and a function call registers no dependency - see AGENT.md on
    // invokables - so this is what a consumer observes to re-rank.
    property int revision: 0

    function recordLaunch(appId) {
        if (!root.ready)
            return;
        const id = String(appId ?? "");
        if (id.length === 0)
            return;
        root.store = Frecency.recordLaunch(root.store, id, Date.now());
        root.revision++;
        writeTimer.restart();
    }

    /** How strongly `appId` is used right now. 0 for anything unknown. */
    function scoreFor(appId, now) {
        return Frecency.scoreFor(root.store, appId, now ?? Date.now());
    }

    Timer {
        id: writeTimer
        interval: 200
        repeat: false
        onTriggered: usageFileView.setText(Frecency.serializeStore(root.store))
    }

    FileView {
        id: usageFileView
        path: Qt.resolvedUrl(root.filePath)
        atomicWrites: true

        onLoaded: {
            // A store that cannot be understood is not repaired and not
            // reported to the user: it is derived data, and an empty store
            // makes every frecency score 0, which makes the boost the
            // identity - so a corrupt file degrades to exactly the match-only
            // ranking that shipped before this existed. The next launch
            // rewrites it.
            const parsed = Frecency.parseStore(usageFileView.text());
            if (parsed === null)
                console.log(`[AppUsage] ${root.filePath} could not be read as launch history; starting fresh`);
            root.store = parsed ?? Frecency.emptyStore();
            root.ready = true;
            root.revision++;
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.log(`[AppUsage] Error loading ${root.filePath}: ${error}`);
            root.store = Frecency.emptyStore();
            root.ready = true;
            root.revision++;
        }
    }

    Component.onCompleted: usageFileView.reload()
}
