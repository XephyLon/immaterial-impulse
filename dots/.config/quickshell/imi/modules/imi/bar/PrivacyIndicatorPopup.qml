import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The privacy indicator's card, in two depths of the SAME surface.
 *
 * Hovering reads: which devices are in use, by which apps. Clicking the pill
 * pins the card and grows it into the acting view - mute, stop, revoke - so the
 * summary is never a thing to dismiss before the controls arrive, and the
 * controls are never one stray pointer-move away from vanishing mid-click.
 *
 * One tree, not two cards: the sections that both depths share are declared
 * once and the action rows appear beside them, so the card grows rather than
 * being replaced.
 */
StyledPopup {
    id: root
    contentPadding: Appearance.spacing.space150

    readonly property bool expanded: root.pinnedOpen

    // A section per active device: an icon + device header, then one line per
    // capturing app (or a fallback line when the app name is unknown).
    component DeviceSection: ColumnLayout {
        id: section
        required property string icon
        required property string label
        required property var entries // list of strings (apps, or a status line)
        Layout.fillWidth: true
        spacing: Appearance.spacing.space25

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space50
            MaterialSymbol {
                text: section.icon
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: section.label
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        Repeater {
            model: section.entries
            delegate: StyledText {
                required property string modelData
                Layout.fillWidth: true
                // Indent under the header's label (icon width + row spacing).
                Layout.leftMargin: Appearance.font.pixelSize.large + Appearance.spacing.space50
                text: modelData
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnSurfaceVariant
                opacity: 0.75
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    // A small icon button for one action on one row.
    component ActionButton: RippleButton {
        id: actionButton
        required property string symbol
        property color symbolColor: Appearance.colors.colOnSurfaceVariant
        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: Appearance.rounding.full
        MaterialSymbol {
            anchors.centerIn: parent
            text: actionButton.symbol
            iconSize: Appearance.font.pixelSize.normal
            color: actionButton.symbolColor
        }
    }

    // One app holding one device, with what can be done about it.
    component AppRow: RowLayout {
        id: appRow
        required property string name
        property var stream: null      // a mic stream, when there is one to act on
        property string note: ""       // shown instead of buttons when nothing can act
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.font.pixelSize.large + Appearance.spacing.space50
        spacing: Appearance.spacing.space50

        StyledText {
            Layout.fillWidth: true
            text: appRow.name
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnSurfaceVariant
            opacity: appRow.stream?.muted ? 0.55 : 0.75
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        StyledText {
            visible: appRow.note.length > 0 && appRow.stream === null
            text: appRow.note
            color: Appearance.colors.colOnSurfaceVariant
            opacity: 0.5
            font.pixelSize: Appearance.font.pixelSize.smallest
        }

        ActionButton {
            visible: appRow.stream !== null
            symbol: appRow.stream?.muted ? "mic_off" : "mic"
            symbolColor: appRow.stream?.muted
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOnSurfaceVariant
            toggled: appRow.stream?.muted ?? false
            releaseAction: () => CaptureControl.toggleStreamMuted(appRow.stream)
        }

        ActionButton {
            // Only where Settings allows taking a stream the app never offered.
            visible: appRow.stream !== null && CaptureControl.allowForceStop
            symbol: "block"
            symbolColor: Appearance.colors.colError
            releaseAction: () => CaptureControl.forceStopStream(appRow.stream)
        }
    }

    Item {
        // Grows with the depth rather than swapping card sizes, so pinning
        // reads as the same surface opening out.
        implicitWidth: root.expanded ? 340 : 260
        implicitHeight: column.implicitHeight
        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: column
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            spacing: Appearance.spacing.space100

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Appearance.spacing.space50
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Privacy")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colError
                }
                StyledText {
                    visible: !root.expanded
                    text: Translation.tr("Click for controls")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.5
                }
            }

            // --- Microphone -------------------------------------------------
            DeviceSection {
                visible: MediaCapture.micActive && !root.expanded
                icon: "mic"
                label: Translation.tr("Microphone")
                entries: MediaCapture.micApps.length > 0
                    ? MediaCapture.micApps
                    : [Translation.tr("In use")]
            }

            ColumnLayout {
                visible: MediaCapture.micActive && root.expanded
                Layout.fillWidth: true
                spacing: Appearance.spacing.space25

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space50
                    MaterialSymbol {
                        text: "mic"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Microphone")
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                Repeater {
                    // Streams, not names: a mute has to address the exact
                    // stream, and two apps can share a name.
                    model: MediaCapture.micStreams
                    delegate: AppRow {
                        required property var modelData
                        name: modelData.name
                        stream: modelData
                    }
                }

                StyledText {
                    // The dot is on but pactl gave nothing to act on - say that
                    // rather than showing an empty section.
                    visible: MediaCapture.micStreams.length === 0
                    Layout.leftMargin: Appearance.font.pixelSize.large + Appearance.spacing.space50
                    text: Translation.tr("In use by an app that cannot be listed")
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.6
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            // --- Camera -----------------------------------------------------
            DeviceSection {
                visible: MediaCapture.cameraActive && !root.expanded
                icon: "videocam"
                label: Translation.tr("Camera")
                entries: MediaCapture.cameraApps.length > 0
                    ? MediaCapture.cameraApps
                    : [Translation.tr("In use")]
            }

            ColumnLayout {
                visible: MediaCapture.cameraActive && root.expanded
                Layout.fillWidth: true
                spacing: Appearance.spacing.space25

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space50
                    MaterialSymbol {
                        text: "videocam"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Camera")
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                Repeater {
                    model: MediaCapture.cameraApps
                    delegate: AppRow {
                        required property string modelData
                        name: modelData
                        // A camera holder is a process with /dev/video open,
                        // not a stream that can be handed back: the only lever
                        // is killing the app, which this panel does not do.
                        note: Translation.tr("no stream control")
                    }
                }
            }

            // --- Screen -----------------------------------------------------
            DeviceSection {
                visible: MediaCapture.screencastActive
                icon: "screen_share"
                label: Translation.tr("Screen")
                entries: [root.expanded
                    ? Translation.tr("Shared by another app - stop it from that app")
                    : Translation.tr("Shared or recorded")]
            }

            ColumnLayout {
                visible: ScreenRecord.recording || ScreenRecord.replaying
                Layout.fillWidth: true
                spacing: Appearance.spacing.space25

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space50
                    MaterialSymbol {
                        text: ScreenRecord.recording ? "screen_record" : "replay"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: ScreenRecord.recording
                            ? Translation.tr("Recording")
                            : Translation.tr("Instant replay")
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Appearance.font.pixelSize.large + Appearance.spacing.space50
                    spacing: Appearance.spacing.space50

                    StyledText {
                        Layout.fillWidth: true
                        text: ScreenRecord.recording
                            ? (ScreenRecord.recordPaused ? Translation.tr("Paused") : Translation.tr("Recording the screen"))
                            : Translation.tr("Buffering the last moments")
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: 0.75
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    ActionButton {
                        visible: root.expanded && ScreenRecord.recording
                        symbol: ScreenRecord.recordPaused ? "play_arrow" : "pause"
                        releaseAction: () => ScreenRecord.togglePauseRecord()
                    }
                    ActionButton {
                        visible: root.expanded && ScreenRecord.recording
                        symbol: "stop"
                        symbolColor: Appearance.colors.colError
                        releaseAction: () => ScreenRecord.stopRecord()
                    }
                    ActionButton {
                        // The replay buffer's whole point: keep what just
                        // happened. Saving does not disarm it.
                        visible: root.expanded && ScreenRecord.replaying
                        symbol: "save"
                        symbolColor: Appearance.colors.colPrimary
                        releaseAction: () => ScreenRecord.saveReplay()
                    }
                    ActionButton {
                        visible: root.expanded && ScreenRecord.replaying
                        symbol: "stop"
                        symbolColor: Appearance.colors.colError
                        releaseAction: () => ScreenRecord.toggleReplay()
                    }
                }
            }

            // --- Portal permissions -----------------------------------------
            ColumnLayout {
                visible: root.expanded
                Layout.fillWidth: true
                Layout.topMargin: Appearance.spacing.space50
                spacing: Appearance.spacing.space25

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space50
                    MaterialSymbol {
                        text: "key"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Granted permissions")
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                Repeater {
                    model: CaptureControl.permissions
                    delegate: ColumnLayout {
                        id: permissionEntry
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        visible: permissionEntry.modelData.apps.length > 0

                        Repeater {
                            model: permissionEntry.modelData.apps
                            delegate: RowLayout {
                                id: permissionAppRow
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.leftMargin: Appearance.font.pixelSize.large + Appearance.spacing.space50
                                spacing: Appearance.spacing.space50

                                StyledText {
                                    Layout.fillWidth: true
                                    text: permissionAppRow.modelData.app
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideMiddle
                                    color: Appearance.colors.colOnSurfaceVariant
                                    opacity: 0.75
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                                ActionButton {
                                    symbol: "block"
                                    symbolColor: Appearance.colors.colError
                                    releaseAction: () => CaptureControl.revokePermission(
                                        permissionEntry.modelData.id, permissionAppRow.modelData.app)
                                }
                            }
                        }
                    }
                }

                StyledText {
                    // Honest about its own reach: only portal-mediated apps
                    // have anything to revoke, so an empty list is the normal
                    // state on a system without sandboxed apps - not a failure,
                    // and not a claim that nothing has the microphone.
                    visible: CaptureControl.permissions.every(p => p.apps.length === 0)
                    Layout.fillWidth: true
                    Layout.leftMargin: Appearance.font.pixelSize.large + Appearance.spacing.space50
                    text: Translation.tr("Nothing granted through the desktop portal. Apps that open the device directly do not appear here.")
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.55
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }
        }
    }

    // Read the store when the controls are actually opened, not on every hover.
    onExpandedChanged: if (root.expanded) CaptureControl.refreshPermissions()
}
