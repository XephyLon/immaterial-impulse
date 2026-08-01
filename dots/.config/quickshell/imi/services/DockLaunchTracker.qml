pragma Singleton

import QtQuick
import Quickshell
import qs.services

/**
 * Tracks dock app launches between the launch click and the window mapping,
 * plus an appeared-once registry so the dock's appear animation only plays
 * the first time an app shows up (TaskbarApps rebuilds its whole model on
 * any toplevel change, recreating every delegate - without this gate the
 * appear pop would replay on all icons every time any window opens/closes).
 */
Singleton {
    id: root

    readonly property int timeoutMs: 10000
    // appId (lowercased) -> Timer; bump revision on every mutation so
    // isLaunching() bindings re-evaluate.
    property var pendingLaunches: ({})
    property var seenAppIds: ({})
    property int revision: 0

    function markLaunching(appId) {
        const key = (appId ?? "").toLowerCase();
        if (!key)
            return;
        if (root.pendingLaunches[key])
            root.pendingLaunches[key].restart();
        else
            root.pendingLaunches[key] = timeoutTimerComponent.createObject(root, { appId: key });
        root.revision++;
    }

    function clearLaunching(appId) {
        const key = (appId ?? "").toLowerCase();
        const timer = root.pendingLaunches[key];
        if (!timer)
            return;
        delete root.pendingLaunches[key];
        timer.destroy();
        root.revision++;
    }

    function isLaunching(appId) {
        void root.revision; // reactive dependency
        return !!root.pendingLaunches[(appId ?? "").toLowerCase()];
    }

    // True exactly once per appearance of an app in the dock. The registry is
    // pruned when the app leaves the dock, so the next open animates again.
    function firstAppearance(appId) {
        const key = (appId ?? "").toLowerCase();
        if (!key || root.seenAppIds[key])
            return false;
        root.seenAppIds[key] = true;
        return true;
    }

    Component {
        id: timeoutTimerComponent
        Timer {
            property string appId
            interval: root.timeoutMs
            running: true
            onTriggered: root.clearLaunching(appId)
        }
    }

    Connections {
        target: TaskbarApps
        function onAppsChanged() {
            // A pending launch resolves as soon as its app has a real window.
            for (const key of Object.keys(root.pendingLaunches)) {
                const entry = TaskbarApps.apps.find(a => a.appId === key && a.toplevels.length > 0);
                if (entry)
                    root.clearLaunching(key);
            }
            // Prune the appeared-once registry for apps that left the dock.
            const present = new Set(TaskbarApps.apps.map(a => a.appId));
            for (const key of Object.keys(root.seenAppIds)) {
                if (!present.has(key))
                    delete root.seenAppIds[key];
            }
        }
    }
}
