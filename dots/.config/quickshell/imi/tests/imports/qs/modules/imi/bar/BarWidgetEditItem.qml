import QtQuick

// Stand-in for the edit-mode overlay BarGroup loads in edit mode. The real one
// pulls in ReorderDragArea and the drag controller; nothing under test here
// drags, so this carries the properties BarGroup writes and nothing else.
Item {
    property var controller: null
    property string bucket: ""
    property string widgetId: ""
    property int visibleIndex: 0
}
