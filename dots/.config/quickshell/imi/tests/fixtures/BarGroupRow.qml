import QtQuick
import QtQuick.Layouts
import qs.modules.imi.bar

// Two BarGroups in a row, the second holding a child shaped like the
// standalone pills: 0 wide when idle, and hidden with it. Built through
// Qt.createComponent by tst_bar_group_collapse.qml, because BarGroup draws
// per-corner radii that Qt below 6.7 does not have - declared inline, the
// whole test file would fail to compile there instead of skipping.
RowLayout {
    spacing: 4
    property alias first: first
    property alias second: second
    property alias secondContent: secondContent

    // Enough of the edit controller for BarWidgetEditItem to bind against
    // when edit mode instantiates it; nothing here drags.
    property QtObject fakeController: QtObject {
        property var bucketNames: ["left"]
        function dropBuckets() { return []; }
        function beginDrag() {}
        function dragMoved() {}
        function commitReorder() {}
        function endDrag() {}
        function removeAt() {}
    }

    BarGroup {
        id: first
        currentIndex: 0
        totalCount: 2
        widgetId: "activeWindow"
        Item { implicitWidth: 40; implicitHeight: 10 }
    }
    BarGroup {
        id: second
        currentIndex: 1
        totalCount: 2
        widgetId: "timerPill"
        editController: fakeController
        Item { id: secondContent; implicitWidth: 0; implicitHeight: 10; visible: implicitWidth > 0 }
    }
}
