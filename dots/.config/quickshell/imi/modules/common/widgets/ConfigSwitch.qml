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
    // A row beneath the description, inside the label block. For detail that
    // belongs with the text rather than with the control - a byline, tags
    // stating a fact about the row. It has to live in here: a call site can
    // only append to the outer row, which puts things beside the switch
    // instead of beside the words they describe.
    property alias detailContent: detailRow.data
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
            RowLayout {
                id: detailRow
                // Fills the label block so a call site can push trailing items
                // to the far edge with a spacer.
                Layout.fillWidth: true
                spacing: Appearance.spacing.space50
                opacity: root.enabled ? 1 : 0.4
            }
        }
        InfoTooltipIcon {
            tooltipText: root.infoText
            opacity: root.enabled ? 1 : 0.4
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
