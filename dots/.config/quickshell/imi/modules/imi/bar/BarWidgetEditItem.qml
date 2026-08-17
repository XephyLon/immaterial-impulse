import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets

/**
 * One bar widget's edit affordances, loaded over the widget by `BarGroup`
 * while Edit Mode is on: the input eater that makes the widget inert, the
 * reorder gesture, and the remove badge.
 *
 * ---- why an eater and not `enabled: false` ---------------------------------
 *
 * `enabled: false` on a MouseArea disables that area and nothing under it
 * (AGENT.md), and disabling the whole subtree instead would run every
 * control's own disabled dim at once - a stack of `opacity: enabled ? 1 :
 * 0.4` multiplying down the tree, which is the doubled-dim defect
 * lint_disabled_opacity.py exists for, reached from above. A covering
 * MouseArea intercepts the click, the hover and the wheel without touching a
 * single binding in the widget below, so the widget keeps drawing exactly
 * what it drew - "edited in place at full size" includes looking like
 * itself.
 *
 * ---- the gesture ------------------------------------------------------------
 *
 * The press lands on the eater; `ReorderDragArea`'s handler takes over past
 * the drag threshold (the DragApps/DockButton arrangement). Everything the
 * gesture learns goes to the controller, which owns the indicator, the ghost
 * and the commit - this file makes no store write of its own.
 *
 * A cancel has two paths in: the exit ladder's `editReorderCancel` (Escape
 * with a bar drag in flight), and the mode ending mid-drag - which destroys
 * this item with the pointer still grabbed, so no release can ever commit;
 * the controller's own editMode guard is the belt over those braces.
 */
Item {
    id: root

    property var controller: null
    property string bucket: ""
    property string widgetId: ""
    property int visibleIndex: 0

    readonly property int bucketIndex: root.controller
        ? root.controller.bucketNames.indexOf(root.bucket) : -1
    readonly property bool dragging: reorder.dragging

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        cursorShape: Qt.SizeAllCursor
        // Wheel is a channel of its own: an unhandled wheel propagates to
        // whatever scrollable the widget carries (workspaces, volume), so the
        // eater has to accept it explicitly.
        onWheel: wheel => {
            wheel.accepted = true;
        }
    }

    ReorderDragArea {
        id: reorder
        anchors.fill: parent
        axis: root.controller?.axis ?? "x"
        bucketsProvider: () => root.controller.dropBuckets()
        onDragStarted: root.controller.beginDrag(root.bucketIndex, root.visibleIndex, root.widgetId)
        onTargetChanged: if (reorder.dragging)
            root.controller.dragMoved(reorder.target, reorder.scenePosition)
        onScenePositionChanged: if (reorder.dragging)
            root.controller.dragMoved(reorder.target, reorder.scenePosition)
        onDropped: target => root.controller.commitReorder(root.bucketIndex, root.visibleIndex, target)
        onDragEnded: root.controller.endDrag()
    }

    Connections {
        target: GlobalStates
        function onEditReorderCancel() {
            if (!reorder.dragging) return;
            reorder.cancel();
            // Cleared now rather than at the release still to come, so the
            // ladder's gestureInFlight is already false for the next Escape.
            root.controller.endDrag();
        }
    }

    EditRemoveBadge {
        anchors.top: parent.top
        anchors.right: parent.right
        z: 2
        // The gesture's dim reads as "this one is moving"; a badge left at
        // full strength on a dimmed slot reads as the one thing still there.
        visible: !root.dragging
        onClicked: root.controller.removeAt(root.bucketIndex, root.visibleIndex)
    }
}
