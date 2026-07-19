import QtQuick
import QtQuick.Layouts
import qs.modules.common

Rectangle {
    id: root

    default property alias content: container.data
    property int padding: Appearance.spacing.space150
    property int spacing: Appearance.spacing.space100

    implicitHeight: 34
    implicitWidth: container.implicitWidth + padding

    radius: Appearance.rounding.full
    color: Appearance.colors.colLayer0
    border.width: Appearance.borderWidth.standard
    border.color: Appearance.colors.colLayer0Border

    RowLayout {
        id: container
        anchors.centerIn: parent
        spacing: root.spacing
    }
}