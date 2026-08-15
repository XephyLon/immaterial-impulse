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

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Whether window regions are being offered, so the target row can show
    // which one the click will land on.
    property bool windowTargeting: false
    // Signals
    signal dismiss()
    signal captureFullScreen()

    // The capture KIND, read off the action rather than stored twice - the
    // action enum already says whether this is a shot or a recording, and a
    // second copy of that fact is a second thing to keep in step.
    readonly property bool recording: root.action === RegionSelection.SnipAction.Record
        || root.action === RegionSelection.SnipAction.RecordWithSound

    // Shot or recording. Both then take whichever TARGET the row beside this
    // one chooses, which is what makes six options out of two controls.
    ToolbarTabBar {
        id: kindBar
        tabButtonList: [
            {"icon": "photo_camera", "name": Translation.tr("Shot")},
            {"icon": "videocam", "name": Translation.tr("Record")}
        ]
        readonly property int kindIndex: root.recording ? 1 : 0
        onKindIndexChanged: if (currentIndex !== kindIndex) currentIndex = kindIndex
        Component.onCompleted: currentIndex = kindIndex
        onCurrentIndexChanged: {
            const wanted = currentIndex === 1
                ? RegionSelection.SnipAction.Record
                : RegionSelection.SnipAction.Copy;
            if (root.action !== wanted) root.action = wanted;
        }
    }

    // The target. Region and Window are modes the selection already knows -
    // Window is the hover-and-click targeting the selector has always had,
    // surfaced so it is discoverable rather than found by accident. Full is
    // an action, not a mode: there is nothing to point at, so it fires.
    IconToolbarButton {
        id: fullScreenButton
        text: "fullscreen"
        onClicked: root.captureFullScreen()
        StyledToolTip {
            text: root.recording ? Translation.tr("Record the whole screen")
                                 : Translation.tr("Capture the whole screen")
        }
    }

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
            const newMode = currentIndex === 0 ? RegionSelection.SelectionMode.RectCorners : RegionSelection.SelectionMode.Circle;
            if (root.selectionMode !== newMode)
                root.selectionMode = newMode;
        }
    }
}
