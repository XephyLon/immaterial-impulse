import qs.modules.common
import QtQuick

MouseArea {
    id: root
    
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
}
