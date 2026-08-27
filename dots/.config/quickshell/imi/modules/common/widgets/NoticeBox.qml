import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property alias materialIcon: icon.text
    property alias text: noticeText.text
    default property alias data: buttonRow.data

    // The container role the notice is drawn in. It is a PAIR rather than one
    // colour: a caller that only re-tints the surface leaves the glyph and the
    // text in the previous role's on-colour, which is a contrast decision made
    // by accident. Primary is what every existing notice draws in; a notice
    // whose state is the reason the surface around it is empty says so in the
    // error roles instead.
    property color colBackground: Appearance.colors.colPrimaryContainer
    property color colOnBackground: Appearance.colors.colOnPrimaryContainer

    radius: Appearance.rounding.normal
    color: root.colBackground
    implicitWidth: mainRowLayout.implicitWidth + mainRowLayout.anchors.margins * 2
    implicitHeight: mainRowLayout.implicitHeight + mainRowLayout.anchors.margins * 2

    RowLayout {
        id: mainRowLayout
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space100
        spacing: Appearance.spacing.space100

        MaterialSymbol {
            id: icon
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignTop
            text: "info"
            iconSize: Appearance.font.pixelSize.huge
            color: root.colOnBackground
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space50

            StyledText {
                id: noticeText
                Layout.fillWidth: true
                text: "Notice message"
                color: root.colOnBackground
                wrapMode: Text.WordWrap
            }

            RowLayout {
                id: buttonRow
                visible: children.length > 0
                Layout.fillWidth: true 
            }
        }
    }
}
