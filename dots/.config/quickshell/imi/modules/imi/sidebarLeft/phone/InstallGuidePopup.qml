pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "phone_cards.js" as PhoneCards

/**
 * What a Phone feature is missing on this machine, and how to install it.
 *
 * `dependencies` is exactly what `PhoneDeps.missingFor(feature)` answers -
 * one row per missing dependency, each carrying a name, a description and the
 * per-distro command table - so this component knows nothing about scrcpy,
 * DroidCam or v4l2loopback and cannot drift from what the probes actually
 * found.
 *
 * The three distro pills preselect from `PhoneDeps.distro`; the arithmetic
 * (which pill, which command, what the one-line preview of a multi-line block
 * is) is phone_cards.js, driven by tests/tst_phone_cards.qml.
 *
 * Copy is `wl-copy -- <text>` as a constant argv. The sibling fork spelled it
 * `bash -c "wl-copy '" + quote(text) + "'"`, which puts its own quoting helper
 * between an install command and a shell.
 */
Item {
    id: root

    // [{ key, name, description, commands: { arch, fedora, debian } }]
    property var dependencies: []
    property string detectedDistro: "unknown"
    property string headerTitle: Translation.tr("Missing dependencies")

    signal closeRequested
    signal recheckRequested

    property string selectedDistro: PhoneCards.initialDistro(root.detectedDistro)

    onVisibleChanged: if (root.visible)
        root.selectedDistro = PhoneCards.initialDistro(root.detectedDistro);

    // A scrim that takes the click, so a click anywhere outside the card
    // dismisses the guide rather than reaching the cards behind it.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.closeRequested()

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colScrim
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Appearance.spacing.space200, 420)
        height: Math.min(parent.height - Appearance.spacing.space200,
                         cardColumn.implicitHeight + Appearance.spacing.space200 * 2)
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2Base

        // The card is not the scrim. Without an area of its own every click
        // inside it falls through to the dismissal below.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: cardColumn
            anchors {
                fill: parent
                margins: Appearance.spacing.space200
            }
            spacing: Appearance.spacing.space150

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space125

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "build"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.headerTitle
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }

                RippleButton {
                    Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space125
                    Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space125
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    onClicked: root.closeRequested()

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer3
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space50

                Repeater {
                    model: PhoneCards.distroPills()

                    delegate: RippleButton {
                        id: pill
                        required property var modelData

                        readonly property bool picked: root.selectedDistro === pill.modelData.key
                        Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space100
                        buttonRadius: Appearance.rounding.full
                        colBackground: pill.picked ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                        colBackgroundHover: pill.picked ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer3Hover
                        colRipple: pill.picked ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer3Active
                        onClicked: root.selectedDistro = pill.modelData.key

                        contentItem: StyledText {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            // A distro's name is its own; nothing to translate.
                            text: pill.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: pill.picked ? Font.DemiBold : Font.Normal
                            color: pill.picked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    visible: PhoneCards.knownDistro(root.detectedDistro)
                    text: Translation.tr("Detected: %1").arg(root.detectedDistro)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }

            StyledFlickable {
                id: dependencyScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: dependencyColumn.implicitHeight
                clip: true

                ColumnLayout {
                    id: dependencyColumn
                    width: dependencyScroll.width
                    spacing: Appearance.spacing.space100

                    Repeater {
                        model: root.dependencies

                        delegate: Rectangle {
                            id: dependencyRow
                            required property var modelData

                            readonly property string command: PhoneCards.commandFor(dependencyRow.modelData, root.selectedDistro)

                            Layout.fillWidth: true
                            Layout.preferredHeight: dependencyBody.implicitHeight + Appearance.spacing.space125 * 2
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colLayer3

                            ColumnLayout {
                                id: dependencyBody
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Appearance.spacing.space125
                                    rightMargin: Appearance.spacing.space125
                                }
                                spacing: Appearance.spacing.space75

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Appearance.spacing.space100

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignTop
                                        text: "error"
                                        fill: 1
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.colors.colError
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Appearance.spacing.space25

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: dependencyRow.modelData.name
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer3
                                            wrapMode: Text.WordWrap
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: dependencyRow.modelData.description
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: commandRow.implicitHeight + Appearance.spacing.space75 * 2
                                    visible: dependencyRow.command.length > 0
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colLayer4

                                    RowLayout {
                                        id: commandRow
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            leftMargin: Appearance.spacing.space100
                                            rightMargin: Appearance.spacing.space75
                                        }
                                        spacing: Appearance.spacing.space75

                                        StyledText {
                                            Layout.fillWidth: true
                                            // The preview is one line; the copy
                                            // takes the whole block, comments
                                            // and all.
                                            text: PhoneCards.firstCommand(dependencyRow.command)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.family: Appearance.font.family.monospace
                                            color: Appearance.colors.colOnLayer4
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        RippleButton {
                                            id: copyButton
                                            property bool copied: false

                                            Layout.preferredWidth: Appearance.font.pixelSize.huge + Appearance.spacing.space100
                                            Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space100
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: Appearance.colors.colSurfaceContainerHighest
                                            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                                            colRipple: Appearance.colors.colSurfaceContainerHighestActive
                                            onClicked: {
                                                Quickshell.execDetached(PhoneCards.copyArgv(dependencyRow.command));
                                                copyButton.copied = true;
                                                copiedTimer.restart();
                                            }

                                            contentItem: MaterialSymbol {
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                text: copyButton.copied ? "check" : "content_copy"
                                                fill: 1
                                                iconSize: Appearance.font.pixelSize.small
                                                color: copyButton.copied ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer4
                                                animateChange: true
                                            }

                                            StyledToolTip {
                                                text: Translation.tr("Copy the install command")
                                            }

                                            Timer {
                                                id: copiedTimer
                                                interval: 1500
                                                onTriggered: copyButton.copied = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("After installing, re-check to verify.")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }

                RippleButton {
                    Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space100
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    onClicked: root.recheckRequested()

                    contentItem: RowLayout {
                        spacing: Appearance.spacing.space50

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "refresh"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Re-check")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }
            }
        }
    }
}
