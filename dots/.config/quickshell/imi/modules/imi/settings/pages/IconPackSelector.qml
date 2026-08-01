import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// A grid of icon-theme cards. Each card previews a few real sample icons pulled
// straight from that theme's directory (by file path), so a theme that is not
// the active one still previews correctly, then applies it on click.
ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: Appearance.spacing.space50

    StyledText {
        text: Translation.tr("Icon pack")
        font.pixelSize: Appearance.font.pixelSize.normal
        font.weight: Font.Medium
        color: Appearance.colors.colOnLayer1
    }

    StyledText {
        visible: !IconThemes.available
        text: IconThemes.loading
            ? Translation.tr("Scanning icon themes…")
            : Translation.tr("No icon themes found.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: Appearance.spacing.space50
        rowSpacing: Appearance.spacing.space50

        Repeater {
            model: IconThemes.themes
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool isActive: modelData.id === IconThemes.activeId
                Layout.fillWidth: true
                implicitHeight: cardCol.implicitHeight + Appearance.spacing.space100 * 2
                radius: Appearance.rounding.normal
                color: cardArea.containsMouse
                    ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                border.width: card.isActive
                    ? Appearance.borderWidth.emphasis : Appearance.borderWidth.standard
                border.color: card.isActive
                    ? Appearance.colors.colPrimary : "transparent"

                MouseArea {
                    id: cardArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: IconThemes.apply(card.modelData.id)
                }

                ColumnLayout {
                    id: cardCol
                    anchors.centerIn: parent
                    width: parent.width - Appearance.spacing.space100 * 2
                    spacing: Appearance.spacing.space50

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Appearance.spacing.space25
                        Repeater {
                            model: card.modelData.sampleIcons
                            delegate: Image {
                                required property string modelData
                                source: "file://" + modelData
                                sourceSize.width: 32
                                sourceSize.height: 32
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Appearance.spacing.space25
                        MaterialSymbol {
                            visible: card.isActive
                            text: "check_circle"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: card.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                            Layout.maximumWidth: card.width - Appearance.spacing.space150
                        }
                    }
                }
            }
        }
    }
}
