pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Window-manager queries and dispatches, normalized for the shell's widgets.
 *
 * This was a facade in front of a swappable compositor backend. There is only
 * one compositor, so the indirection is gone and what was HyprlandBackend now
 * lives here directly - the consumer-facing API is unchanged.
 */
Singleton {
    id: root

    property var windowList: []
    property var workspaces: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    readonly property var focusedMonitor: Hyprland.focusedMonitor

    function normalizeWindow(w) {
        return {
            id: w.address,
            address: w.address,
            title: w.title,
            appId: w.class,
            workspaceId: w.workspace?.id ?? -1,
            focused: w.address === HyprlandData.activeWorkspace?.lastwindow
        };
    }

    function switchWorkspaceRelative(direction) {
        Hyprland.dispatch(`hl.dsp.focus({workspace = "r${direction === "next" ? "+1" : "-1"}"})`);
    }
    function focusWindow(id) {
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${id}" })`);
    }
    function closeWindow(id) {
        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${id}" })`);
    }
    function switchWorkspace(id) {
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${id} })`);
    }
    function moveWindowToWorkspace(id, wsId) {
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${wsId}, follow = false, window = "address:${id}" })`);
    }

    function monitorFor(screen) {
        return Hyprland.monitorFor(screen);
    }

    function activeWorkspaceForMonitor(monitorName) {
        const m = Hyprland.monitors.values.find(mm => mm.name === monitorName);
        return m?.activeWorkspace ? { id: m.activeWorkspace.id } : null;
    }

    function biggestWindowForWorkspace(wsId) {
        return HyprlandData.biggestWindowForWorkspace(wsId);
    }

    function fullscreenOnMonitor(monitorName) {
        const wsList = Hyprland.workspaces.values.filter(ws => ws.monitor && ws.monitor.name === monitorName);
        return wsList.some(ws => ws.active && ws.toplevels.values.some(w => w.wayland?.fullscreen));
    }

    function monitorGeometry(screen) {
        const m = Hyprland.monitorFor(screen);
        if (!m)
            return { x: 0, y: 0, scale: 1 };
        return { x: m.x, y: m.y, scale: m.scale };
    }

    function refresh() {
        windowList = HyprlandData.windowList.map(normalizeWindow);
        workspaces = HyprlandData.workspaces;
        workspaceById = HyprlandData.workspaceById;
        activeWorkspace = HyprlandData.activeWorkspace;
        monitors = HyprlandData.monitors;
    }

    Component.onCompleted: refresh()

    Connections {
        target: HyprlandData
        function onWindowListChanged() { root.refresh() }
        function onWorkspacesChanged() { root.refresh() }
        function onMonitorsChanged() { root.refresh() }
    }
}
