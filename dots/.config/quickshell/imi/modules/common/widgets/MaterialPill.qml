import qs.modules.common
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property bool vertical: false
    property real crossAxisSize: 32
    property real mainAxisPadding: Appearance.spacing.space125
    property real contentSpacing: Appearance.spacing.space50
    property real contentTopMargin: Appearance.spacing.space50
    property color bgColor: Appearance.colors.colPrimaryContainer

    default property alias content: contentLayout.children

    color: root.bgColor
    radius: Appearance.rounding.full
    implicitWidth: root.vertical
        ? root.crossAxisSize
        : contentLayout.implicitWidth + root.mainAxisPadding
    implicitHeight: root.vertical
        ? contentLayout.implicitHeight + root.mainAxisPadding
        : root.crossAxisSize

    GridLayout {
        id: contentLayout
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.vertical ? root.contentTopMargin / 2 : 0
        columns: root.vertical ? 1 : -1
        rowSpacing: root.contentSpacing
        columnSpacing: root.contentSpacing
    }
}