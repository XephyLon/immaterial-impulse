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
    // A full-width row beneath everything else, for detail about the row - a
    // byline, tags stating a fact about it. It spans the whole control rather
    // than just the label block, so a call site can push trailing items to the
    // same right edge the switch sits on; inside the label block they would
    // stop short of the switch and hang diagonally beneath it.
    //
    // Empty for every caller that does not set it, and an empty RowLayout has
    // no height, so this costs nothing elsewhere.
    property alias detailContent: detailRow.data
    // Sits on the label's own line, immediately after it. For a secondary
    // phrase that belongs to the title rather than under it - a byline, a
    // version. The label is one StyledText, so a caller cannot mix type sizes
    // into it directly.
    property alias titleContent: titleRow.data
    colBackgroundHover: "transparent"

    Layout.fillWidth: true
    implicitHeight: contentItem.implicitHeight + 8 
    font.pixelSize: Appearance.font.pixelSize.small

    onClicked: checked = !checked

    contentItem: ColumnLayout {
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
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
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space100

                    StyledText {
                        id: labelWidget
                        text: root.text
                        textFormat: Text.PlainText
                        font: root.font
                        color: Appearance.colors.colOnSecondaryContainer
                        opacity: root.enabled ? 1 : 0.4
                    }
                    RowLayout {
                        id: titleRow
                        Layout.alignment: Qt.AlignBaseline
                        spacing: Appearance.spacing.space50
                        opacity: root.enabled ? 1 : 0.4
                    }
                    // Keeps the label left-aligned now that it no longer fills
                    // the row itself.
                    Item { Layout.fillWidth: true }
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

            StyledSwitch {
                id: switchWidget
                down: root.down
                Layout.fillWidth: false
                checked: root.checked
                onClicked: root.clicked()
            }
        }

        RowLayout {
            id: detailRow
            Layout.fillWidth: true
            spacing: Appearance.spacing.space50
            opacity: root.enabled ? 1 : 0.4
        }
    }
}
