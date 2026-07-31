pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Hyprland-only facade. Upstream abstracts compositors behind this
    // service; this fork supports Hyprland exclusively, so the detection and
    // alternative backends are removed while the consumer-facing API stays
    // merge-compatible.
    readonly property string compositor: "hyprland"
    property QtObject backend: null

    function switchWorkspaceRelative(direction) { backend?.switchWorkspaceRelative(direction) }

    Component { id: hyprlandComp; HyprlandBackend {} }

    Component.onCompleted: {
        backend = hyprlandComp.createObject(root);
    }

    // Proxies
    readonly property var windowList: backend?.windowList ?? []
    readonly property var workspaces: backend?.workspaces ?? []
    readonly property var workspaceById: backend?.workspaceById ?? ({})
    readonly property var activeWorkspace: backend?.activeWorkspace ?? null
    readonly property var monitors: backend?.monitors ?? []
    readonly property var focusedMonitor: backend?.focusedMonitor ?? null

    function focusWindow(id) { backend?.focusWindow(id) }
    function closeWindow(id) { backend?.closeWindow(id) }
    function switchWorkspace(id) { backend?.switchWorkspace(id) }
    function moveWindowToWorkspace(id, wsId) { backend?.moveWindowToWorkspace(id, wsId) }
    function monitorFor(screen) { return backend?.monitorFor(screen) ?? null }
    function activeWorkspaceForMonitor(monitorName) { return backend?.activeWorkspaceForMonitor(monitorName) ?? null }
    function biggestWindowForWorkspace(wsId) { return backend?.biggestWindowForWorkspace(wsId) ?? null }
    function fullscreenOnMonitor(monitorName) { return backend?.fullscreenOnMonitor(monitorName) ?? false }
    function monitorGeometry(screen) { return backend?.monitorGeometry(screen) ?? { x: 0, y: 0, scale: 1 } }
}
