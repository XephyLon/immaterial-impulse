import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string value: ""

    property color avatarColor: Appearance.colors.colPrimary
    property color avatarOnColor: Appearance.colors.colOnPrimary
    property color iconPanelColor: ColorUtils.transparentize(Appearance?.colors.colPrimaryContainer, 0.9)
    property color iconOnColor: Appearance.colors.colOnPrimaryContainer

    implicitWidth: 260
    implicitHeight: Math.max(64, cardRow.implicitHeight)
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: "transparent"
    clip: true

    RowLayout {
        id: cardRow
        anchors.fill: parent
        spacing: 0

        // Letter avatar
        Rectangle {
            Layout.leftMargin: 14
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 40
            implicitHeight: 40
            radius: width / 2
            color: root.avatarColor

            StyledText {
                anchors.centerIn: parent
                text: root.label.length > 0 ? root.label.charAt(0).toUpperCase() : ""
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: root.avatarOnColor
            }
        }

        // Header / Subhead
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.value
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 72
            color: root.iconPanelColor
            topRightRadius: root.radius
            bottomRightRadius: root.radius

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: Appearance.font.pixelSize.hugeass
                color: root.iconOnColor
            }
        }
    }
}