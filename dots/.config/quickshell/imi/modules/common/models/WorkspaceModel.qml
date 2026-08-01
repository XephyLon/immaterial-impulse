pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common as C

NestableObject {
    id: root

    required property var screen
    readonly property string monitorName: screen?.name ?? ""

    readonly property var hyprMonitor: Hyprland.monitorFor(screen)
    readonly property var liveMonitorData: HyprlandData.monitors.find(m => m.id === hyprMonitor?.id)

    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    readonly property int shownCount: C.Config.options.bar.workspaces.shown
    readonly property bool showAllMonitors: C.Config.options.bar.workspaces.showAllMonitors

    readonly property int activeNumber: hyprMonitor?.activeWorkspace?.id ?? 1

    readonly property bool currentWorkspaceNotFake: activeWindow?.activated ?? false // Active empty workspace = fake. At least, that's how I like to call it.
    readonly property int fakeWorkspace: currentWorkspaceNotFake ? -9999 : activeNumber

    readonly property int group: Math.floor((activeNumber - 1) / shownCount)

    readonly property var specialWorkspace: liveMonitorData?.specialWorkspace
    readonly property string specialWorkspaceName: specialWorkspace?.name.replace("special:", "") ?? "special"
    readonly property bool specialWorkspaceActive: specialWorkspaceName !== ""

    property list<bool> occupied: []
    property list<var> biggestWindow: occupied.map((_, index) => {
        const number = getWorkspaceIdAt(index)
        return root.biggestWindowForNumber(number)
    })

    function getWorkspaceId(group, index) {
        return group * root.shownCount + index + 1
    }
    function getWorkspaceIdAt(index) {
        return root.getWorkspaceId(root.group, index)
    }

    function biggestWindowForNumber(number) {
        return HyprlandData.biggestWindowForWorkspace(number)
    }

    function updateWorkspaceOccupied() {
        root.occupied = Array.from({ length: root.shownCount }, (_, i) => {
            const thisWorkspaceId = getWorkspaceId(root.group, i)
            return Hyprland.workspaces.values.some(ws => ws.id === thisWorkspaceId)
        })
    }

    Component.onCompleted: updateWorkspaceOccupied()

    // Hyprland
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            root.updateWorkspaceOccupied()
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.updateWorkspaceOccupied()
        }
    }


    onGroupChanged: {
        updateWorkspaceOccupied()
    }
    onShowAllMonitorsChanged: {
        updateWorkspaceOccupied();
    }
}