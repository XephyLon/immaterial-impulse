import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets

/**
 * One island item's edit affordances, loaded over the slot by `LockSurface`
 * while the Lockscreen tab's preview is editing: the input eater and the
 * reorder gesture - `BarWidgetEditItem`'s shape without the remove badge,
 * because island items are hidden through the lock.show* presence booleans
 * rather than removed one by one.
 *
 * The eater is the same reasoning as the bar's: the preview's controls are
 * already guarded handler by handler, but a covering MouseArea is what stops
 * their ripples answering a press that is about to become a drag, and what
 * gives the slot the move cursor - without touching a single binding in the
 * item below, so the preview keeps looking like the lock screen.
 *
 * The gesture is `ReorderDragArea` (the press lands on the eater; the
 * handler takes over past the drag threshold), and everything it learns goes
 * to the island's controller, which owns the indicator and the commit - this
 * file makes no store write of its own.
 */
Item {
    id: root
    objectName: "lockIslandEditItem"

    property var controller: null
    property int renderedIndex: 0

    readonly property bool dragging: reorder.dragging

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        cursorShape: Qt.SizeAllCursor
        onWheel: wheel => {
            wheel.accepted = true;
        }
    }

    ReorderDragArea {
        id: reorder
        anchors.fill: parent
        axis: "x"
        bucketsProvider: () => root.controller.dropBuckets()
        onDragStarted: root.controller.beginDrag(root.renderedIndex)
        onTargetChanged: if (reorder.dragging) root.controller.dragMoved(reorder.target)
        onDropped: target => root.controller.commitReorder(root.renderedIndex, target)
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
}
