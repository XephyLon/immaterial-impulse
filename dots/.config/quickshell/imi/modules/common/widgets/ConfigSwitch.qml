import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RippleButton {
    id: root
    property string buttonIcon
    property string description: ""
    // Shown as a hoverable "i" beside the control rather than inline, so a long
    // explanation doesn't stretch the row.
    property string infoText: ""
    property alias iconSize: iconWidget.iconSize
    // Content sitting immediately before the switch - tags, badges, anything
    // stating a fact about the row. It has to live in here because the switch
    // does: a call site appending to its own row can only land to the *right*
    // of the switch, which reads as belonging to whatever follows.
    property alias trailingContent: trailingRow.data
    colBackgroundHover: "transparent"

    Layout.fillWidth: true
    implicitHeight: contentItem.implicitHeight + 8 
    font.pixelSize: Appearance.font.pixelSize.small

    onClicked: checked = !checked

    contentItem: RowLayout {
        spacing: Appearance.spacing.space150
        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            opacity: root.enabled ? 1 : 0.4
            iconSize: Appearance.font.pixelSize.larger
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                id: labelWidget
                Layout.fillWidth: true
                text: root.text
                textFormat: Text.PlainText
                font: root.font
                color: Appearance.colors.colOnSecondaryContainer
                opacity: root.enabled ? 1 : 0.4
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.description.length > 0
                text: root.description
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                opacity: root.enabled ? 1 : 0.4
            }
        }
        InfoTooltipIcon {
            tooltipText: root.infoText
            opacity: root.enabled ? 1 : 0.4
        }

        RowLayout {
            id: trailingRow
            Layout.alignment: Qt.AlignVCenter
            spacing: Appearance.spacing.space50
        }

        StyledSwitch {
            id: switchWidget
            down: root.down
            Layout.fillWidth: false
            checked: root.checked
            onClicked: root.clicked()
        }
    }
}
