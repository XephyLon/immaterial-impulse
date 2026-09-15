import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.modes

/**
 * The mode pill's card: the mode as the hero (its glyph on its colour, who
 * started it and when it ends), the routines running alongside it as chips
 * that stop on their ×, and the two controls - manage, end.
 */
StyledPopup {
    id: root

    readonly property var mode: Modes.activeMode
    readonly property string colorKey: root.mode?.color ?? ""

    ColumnLayout {
        spacing: Appearance.spacing.space150
        implicitWidth: 260

        // The header row is this popup's HERO - the first drawn section,
        // whose height the card opens at.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Appearance.spacing.space50
            spacing: Appearance.spacing.space100

            MaterialShapeWrappedMaterialSymbol {
                shape: MaterialShape.Shape.ClamShell
                text: root.mode?.icon ?? "tune"
                iconSize: Appearance.font.pixelSize.large
                implicitSize: 36
                color: ModeUi.container(root.colorKey)
                colSymbol: ModeUi.onContainer(root.colorKey)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -Appearance.spacing.space50

                StyledText {
                    text: root.mode?.name ?? ""
                    font {
                        weight: Font.Medium
                        pixelSize: Appearance.font.pixelSize.normal
                    }
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.6
                    text: {
                        let line = Translation.tr("Started %1 · %2")
                            .arg(Modes.sourceText(Modes.activeSource)).arg(ModeUi.clock(Modes.activeSince));
                        if (Modes.activeEndsAt > 0)
                            line += " · " + Translation.tr("ends %1").arg(ModeUi.clock(Modes.activeEndsAt));
                        return line;
                    }
                }
            }
        }

        // Routines running alongside the mode; × stops one.
        Flow {
            Layout.fillWidth: true
            visible: Modes.routineRuns.length > 0
            spacing: Appearance.spacing.space50

            Repeater {
                model: Modes.routineRuns

                delegate: Rectangle {
                    id: runChip
                    required property var modelData
                    readonly property var routine: Modes.routineById(runChip.modelData.id)
                    readonly property color onColor: ModeUi.onContainer(runChip.routine?.color ?? "")

                    implicitWidth: runRow.implicitWidth + Appearance.spacing.space150 * 2
                    implicitHeight: Appearance.sizes.barStandalonePillHeight
                    radius: Appearance.rounding.full
                    color: ModeUi.container(runChip.routine?.color ?? "")

                    RowLayout {
                        id: runRow
                        anchors.centerIn: parent
                        spacing: Appearance.spacing.space50

                        MaterialSymbol {
                            text: runChip.routine?.icon ?? "bolt"
                            iconSize: Appearance.font.pixelSize.large
                            color: runChip.onColor
                        }
                        StyledText {
                            text: runChip.routine?.name ?? runChip.modelData.id
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: runChip.onColor
                        }
                        MouseArea {
                            implicitWidth: Appearance.font.pixelSize.large
                            implicitHeight: Appearance.font.pixelSize.large
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Modes.stopRoutine(runChip.modelData.id, "manual")
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.large
                                color: runChip.onColor
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            RippleButton {
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                onClicked: {
                    root.pinnedOpen = false;
                    GlobalStates.modesOpen = true;
                }
                // A Control positions its own content item, so the row centres
                // inside a stretched Item rather than anchoring itself.
                contentItem: Item {
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Appearance.spacing.space50
                        MaterialSymbol {
                            text: "tune"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            text: Translation.tr("Manage")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }

            RippleButton {
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.full
                // Ending a mode you started is the ordinary way out, not an
                // error - and not a second tonal chip either: one weighted
                // action (Manage) and one flat exit, the dialog rule's shape.
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: {
                    root.pinnedOpen = false;
                    Modes.deactivate("manual");
                }
                // A Control positions its own content item, so the row centres
                // inside a stretched Item rather than anchoring itself.
                contentItem: Item {
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Appearance.spacing.space50
                        MaterialSymbol {
                            text: "stop"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: Translation.tr("End")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }
            }
        }
    }
}
