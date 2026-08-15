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
    // action enum already says whether this is a shot or a recording.
    //
    // Recomputed in a handler rather than bound. `action` is a two-way
    // Synchronizer property: this toolbar writes it and the selector writes it
    // back, so a binding derived from it has its own dependency reassigned
    // partway through the chain it starts - which is what QML was reporting as
    // a binding loop on this property and on the tab bars' index below.
    property bool recording: false
    function kindFromAction() {
        root.recording = root.action === RegionSelection.SnipAction.Record
            || root.action === RegionSelection.SnipAction.RecordWithSound;
        const index = root.recording ? 1 : 0;
        if (kindBar.currentIndex !== index) kindBar.currentIndex = index;
    }
    function modeFromSelection() {
        const index = root.selectionMode === RegionSelection.SelectionMode.RectCorners ? 0 : 1;
        if (tabBar.currentIndex !== index) tabBar.currentIndex = index;
    }
    onActionChanged: root.kindFromAction()
    onSelectionModeChanged: root.modeFromSelection()
    Component.onCompleted: {
        root.kindFromAction();
        root.modeFromSelection();
    }

    // Shot or recording. Both then take whichever TARGET the row beside this
    // one chooses, which is what makes six options out of two controls.
    ToolbarTabBar {
        id: kindBar
        tabButtonList: [
            {"icon": "photo_camera", "name": Translation.tr("Shot")},
            {"icon": "videocam", "name": Translation.tr("Record")}
        ]
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
        // Driven from the toolbar's own handlers (see modeFromSelection): the
        // index is never bound to `selectionMode`, only assigned to it and
        // from it, so neither direction is a binding that can loop.
        onCurrentIndexChanged: {
            const newMode = currentIndex === 0 ? RegionSelection.SelectionMode.RectCorners : RegionSelection.SelectionMode.Circle;
            if (root.selectionMode !== newMode)
                root.selectionMode = newMode;
        }
    }
}
