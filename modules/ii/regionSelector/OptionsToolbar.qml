pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Signals
    signal dismiss()

    ToolbarTabBar {
        id: tabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")}
        ]
        // currentIndex aliases TabBar's own property, which the TabBar writes to
        // as well, so binding it here while also writing back from the change
        // handler is a binding loop. Sync both directions imperatively instead.
        readonly property int modeIndex: root.selectionMode === RegionSelection.SelectionMode.RectCorners ? 0 : 1

        onModeIndexChanged: if (currentIndex !== modeIndex) currentIndex = modeIndex
        Component.onCompleted: currentIndex = modeIndex
        onCurrentIndexChanged: {
            const mode = currentIndex === 0 ? RegionSelection.SelectionMode.RectCorners : RegionSelection.SelectionMode.Circle;
            if (root.selectionMode !== mode) root.selectionMode = mode;
        }
    }
}
