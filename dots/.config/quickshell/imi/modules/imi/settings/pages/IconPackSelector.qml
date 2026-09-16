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

    // The shared placeholder fills and centres itself in what it is given, so
    // in this column it gets an item with its own height.
    Item {
        Layout.fillWidth: true
        implicitHeight: noIconThemesPlaceholder.visible ? 200 : 0

        PagePlaceholder {
            id: noIconThemesPlaceholder
            shown: !IconThemes.available
            readonly property bool scanning: IconThemes.loading
            icon: noIconThemesPlaceholder.scanning ? "hourglass" : "imagesmode"
            shape: MaterialShape.Shape.Clover4Leaf
            title: noIconThemesPlaceholder.scanning
                ? Translation.tr("Scanning icon themes…")
                : Translation.tr("No icon themes found")
            description: noIconThemesPlaceholder.scanning
                ? ""
                : Translation.tr("Install one and it shows up here.")
            descriptionHorizontalAlignment: Text.AlignHCenter
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: Appearance.spacing.space50
        rowSpacing: Appearance.spacing.space50

        Repeater {
            model: IconThemes.themes
            // A button, not a plate with a MouseArea: the cards are picked, so
            // they hover, press and ripple like the rest.
            delegate: RippleButton {
                id: card
                required property var modelData
                readonly property bool isActive: modelData.id === IconThemes.activeId
                Layout.fillWidth: true
                padding: Appearance.spacing.space100
                implicitHeight: cardCol.implicitHeight + Appearance.spacing.space100 * 2
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                // The active card is marked by its border and its check, not
                // by a plate of its own - so the toggled tones are the same
                // layer pair.
                toggled: card.isActive
                colBackgroundToggled: Appearance.colors.colLayer2
                colBackgroundToggledHover: Appearance.colors.colLayer2Hover
                colRippleToggled: Appearance.colors.colLayer2Active
                border: true
                borderWidth: card.isActive
                    ? Appearance.borderWidth.emphasis : Appearance.borderWidth.standard
                colBorder: card.isActive
                    ? Appearance.colors.colPrimary : "transparent"

                onClicked: IconThemes.apply(card.modelData.id)

                contentItem: ColumnLayout {
                    id: cardCol
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
