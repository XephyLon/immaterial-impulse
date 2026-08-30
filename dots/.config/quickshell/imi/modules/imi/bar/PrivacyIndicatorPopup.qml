import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The privacy indicator's card, at two depths of the SAME tree.
 *
 * Hovering reads: which devices are in use, by which apps. Clicking the pill
 * pins the card and the controls arrive in it - mute, stop, revoke - so the
 * summary is never a thing to dismiss before the controls appear, and the
 * controls are never one stray pointer-move away from vanishing mid-click.
 *
 * ONE tree, not two. Every section, header, icon and label is declared once and
 * stays put across the depth change; the only things that appear are the
 * buttons and the permission list, and they arrive by growing out of zero width
 * rather than by being swapped in. The first version declared each section
 * twice and toggled `visible` between the copies, which destroyed and rebuilt
 * the shared parts mid-transition: the header and the icons blinked out for a
 * few frames while the buttons popped in at full size. A morph cannot happen
 * between two trees - only within one.
 */
StyledPopup {
    id: root
    contentPadding: Appearance.spacing.space150

    readonly property bool expanded: root.pinnedOpen

    // The card this content sits on animates its own width and height, and
    // centres the content while it does. So the content's size must travel on
    // exactly the card's tier: slower and it is cropped by a card that has
    // already grown, faster and it overflows a card still catching up - which
    // is what clipped the header off the top mid-transition. Same duration,
    // same curve, no drift.
    readonly property int revealDuration: Appearance.animation.elementMove.duration
    readonly property list<real> revealCurve: Appearance.animationCurves.expressiveDefaultSpatial
    readonly property int fadeDuration: Appearance.animation.elementMoveFast.duration
    readonly property list<real> fadeCurve: Appearance.animationCurves.expressiveEffects

    // The indent that lines a section's plate up under its header's label:
    // the shaped icon's width plus the header row's gap.
    readonly property real rowIndent: 32 + Appearance.spacing.space100

    // A section header: the glyph in its Material shape - the same treatment
    // the clock and weather cards carry - with the label beside it. The
    // shape varies per section, which is the design language's way of making
    // a list of headers scannable; the error-toned pair is the title's.
    component SectionHeader: RowLayout {
        id: header
        required property string icon
        required property string label
        property var shape: MaterialShape.Shape.Clover4Leaf
        property bool errorTone: false
        Layout.fillWidth: true
        spacing: Appearance.spacing.space100
        MaterialShapeWrappedMaterialSymbol {
            wrappedShape: header.shape
            text: header.icon
            iconSize: Appearance.font.pixelSize.normal
            implicitSize: 32
            color: header.errorTone
                ? Appearance.colors.colErrorContainer
                : Appearance.colors.colPrimaryContainer
            colSymbol: header.errorTone
                ? Appearance.colors.colError
                : Appearance.colors.colPrimary
        }
        StyledText {
            Layout.fillWidth: true
            text: header.label
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
        }
    }

    // The tonal plate a section's rows sit on - the grouped-surface reading
    // every settings page and the clock popup's task cards already have,
    // instead of bare text floating on the card.
    component SectionPlate: Rectangle {
        id: plate
        default property alias content: plateColumn.data
        Layout.fillWidth: true
        Layout.leftMargin: root.rowIndent
        implicitHeight: plateColumn.implicitHeight + Appearance.spacing.space100 * 2
        radius: Appearance.rounding.normal
        color: Appearance.colors.colSurfaceContainerHigh
        Behavior on implicitHeight {
            NumberAnimation {
                duration: root.revealDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.revealCurve
            }
        }
        ColumnLayout {
            id: plateColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: Appearance.spacing.space150
                rightMargin: Appearance.spacing.space100
            }
            spacing: Appearance.spacing.space25
        }
    }

    // A control that grows in from nothing along the row. Width carries the
    // layout (so the label beside it slides rather than jumps), opacity and
    // scale carry the arrival.
    component ActionSlot: Item {
        id: slot
        property bool on: false
        default property alias content: holder.data
        readonly property real slotSize: 30
        implicitWidth: on ? slotSize : 0
        implicitHeight: slotSize
        opacity: on ? 1 : 0
        scale: on ? 1 : 0.6
        clip: true
        visible: implicitWidth > 0.5
        Behavior on implicitWidth {
            NumberAnimation {
                duration: root.revealDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.revealCurve
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: root.fadeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.fadeCurve
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.revealDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.revealCurve
            }
        }
        Item {
            id: holder
            width: slot.slotSize
            height: slot.slotSize
            anchors.centerIn: parent
        }
    }

    // A block that opens downward rather than appearing: its height is what
    // travels, and its contents ride along at full strength - a fade would make
    // the text arrive separately from the row it belongs to.
    component Reveal: Item {
        id: reveal
        property bool shown: false
        default property alias content: revealColumn.data
        Layout.fillWidth: true
        implicitHeight: reveal.shown ? revealColumn.implicitHeight : 0
        clip: true
        visible: implicitHeight > 0.5
        Behavior on implicitHeight {
            NumberAnimation {
                duration: root.revealDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.revealCurve
            }
        }
        ColumnLayout {
            id: revealColumn
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: Appearance.spacing.space25
        }
    }

    component ActionButton: RippleButton {
        id: actionButton
        required property string symbol
        property bool errorTone: false
        property color symbolColor: actionButton.errorTone
            ? Appearance.colors.colOnErrorContainer
            : Appearance.colors.colOnSecondaryContainer
        anchors.fill: parent
        buttonRadius: Appearance.rounding.full
        // Tonal, not bare glyphs on the plate: a control should look like
        // one. The destructive pair sits on the error container.
        colBackground: actionButton.errorTone
            ? Appearance.colors.colErrorContainer
            : Appearance.colors.colSecondaryContainer
        colBackgroundHover: actionButton.errorTone
            ? Appearance.colors.colErrorContainerHover
            : Appearance.colors.colSecondaryContainerHover
        colRipple: actionButton.errorTone
            ? Appearance.colors.colErrorContainerActive
            : Appearance.colors.colSecondaryContainerActive
        MaterialSymbol {
            anchors.centerIn: parent
            text: actionButton.symbol
            iconSize: Appearance.font.pixelSize.normal
            color: actionButton.symbolColor
        }
    }

    // One app holding one device. The name is declared once and never moves;
    // the buttons grow in beside it when the card is pinned.
    component AppRow: RowLayout {
        id: appRow
        required property string name
        property var stream: null      // a mic stream, when there is one to act on
        property string note: ""       // what to say when nothing can act
        Layout.fillWidth: true
        spacing: Appearance.spacing.space50

        StyledText {
            Layout.fillWidth: true
            text: appRow.name
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnSurfaceVariant
            // A muted app is still listed, just quieter than one that is not.
            opacity: appRow.stream?.muted ? 0.55 : 0.75
            font.pixelSize: Appearance.font.pixelSize.smaller
            Behavior on opacity {
                NumberAnimation {
                    duration: root.fadeDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.fadeCurve
                }
            }
        }

        StyledText {
            visible: opacity > 0.01
            opacity: (root.expanded && appRow.note.length > 0 && appRow.stream === null) ? 0.5 : 0
            text: appRow.note
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smallest
            Behavior on opacity {
                NumberAnimation {
                    duration: root.fadeDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.fadeCurve
                }
            }
        }

        ActionSlot {
            on: root.expanded && appRow.stream !== null
            ActionButton {
                symbol: appRow.stream?.muted ? "mic_off" : "mic"
                toggled: appRow.stream?.muted ?? false
                releaseAction: () => CaptureControl.toggleStreamMuted(appRow.stream)
            }
        }

        ActionSlot {
            // Only where Settings allows taking a stream the app never offered.
            on: root.expanded && appRow.stream !== null && CaptureControl.allowForceStop
            ActionButton {
                symbol: "block"
                errorTone: true
                releaseAction: () => CaptureControl.forceStopStream(appRow.stream)
            }
        }
    }

    // A device that is in use, its apps, and what can be done about them.
    // `streams` wins over `entries` where it exists, because a mute has to
    // address the exact stream and two apps can share a name.
    component DeviceSection: ColumnLayout {
        id: section
        required property string icon
        required property string label
        property var shape: MaterialShape.Shape.Clover4Leaf
        property var entries: []
        property var streams: []
        property string rowNote: ""
        Layout.fillWidth: true
        spacing: Appearance.spacing.space50

        SectionHeader {
            icon: section.icon
            label: section.label
            shape: section.shape
        }

        SectionPlate {
            Repeater {
                model: section.streams.length > 0 ? section.streams : section.entries
                delegate: AppRow {
                    required property var modelData
                    // Streams arrive as objects, plain listings as strings.
                    name: (modelData && modelData.name !== undefined) ? modelData.name : String(modelData)
                    stream: (modelData && modelData.name !== undefined) ? modelData : null
                    note: section.rowNote
                }
            }
        }
    }

    Item {
        id: contentRoot
        implicitWidth: root.expanded ? 360 : 280
        implicitHeight: column.implicitHeight

        // The card follows this size instead of easing toward it (see
        // StyledPopup.contentDrivesSize), so this Behavior is the ONE animation
        // in the transition: every element that exists at both depths stays on
        // screen and travels, and nothing is clipped, because the card is
        // exactly as big as its content on every frame.
        Behavior on implicitWidth {
            NumberAnimation {
                duration: root.revealDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.revealCurve
            }
        }

        ColumnLayout {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: Appearance.spacing.space100

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100
                MaterialShapeWrappedMaterialSymbol {
                    wrappedShape: MaterialShape.Shape.Cookie9Sided
                    text: "privacy_tip"
                    iconSize: Appearance.font.pixelSize.normal
                    implicitSize: 32
                    color: Appearance.colors.colErrorContainer
                    colSymbol: Appearance.colors.colError
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Privacy")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colError
                }
                StyledText {
                    // Fades rather than disappearing: it is the one label whose
                    // job ends when the card is pinned.
                    visible: opacity > 0.01
                    opacity: root.expanded ? 0 : 0.5
                    text: Translation.tr("Click for controls")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.fadeDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: root.fadeCurve
                        }
                    }
                }
            }

            DeviceSection {
                visible: MediaCapture.micActive
                icon: "mic"
                label: Translation.tr("Microphone")
                shape: MaterialShape.Shape.Cookie12Sided
                streams: MediaCapture.micStreams
                entries: MediaCapture.micApps.length > 0
                    ? MediaCapture.micApps
                    : [Translation.tr("In use")]
            }

            DeviceSection {
                visible: MediaCapture.cameraActive
                icon: "videocam"
                label: Translation.tr("Camera")
                shape: MaterialShape.Shape.Clover4Leaf
                entries: MediaCapture.cameraApps.length > 0
                    ? MediaCapture.cameraApps
                    : [Translation.tr("In use")]
                // A camera holder is a process with /dev/video open, not a
                // stream that can be handed back: the only lever is killing the
                // app, which this panel does not do. Said, rather than left as
                // a silence that would read as an assurance.
                rowNote: Translation.tr("no stream control")
            }

            DeviceSection {
                visible: MediaCapture.screencastActive
                icon: "screen_share"
                label: Translation.tr("Screen")
                shape: MaterialShape.Shape.Slanted
                // Portal casts carry their app identity through PipeWire;
                // screencopy and kms captures are anonymous by nature, so
                // the generic line survives as the honest fallback.
                entries: MediaCapture.screencastApps.length > 0
                    ? MediaCapture.screencastApps
                    : [Translation.tr("Shared or recorded")]
                rowNote: Translation.tr("stop it from that app")
            }

            // The shell's own captures, which it CAN act on.
            ColumnLayout {
                visible: ScreenRecord.recording || ScreenRecord.replaying
                Layout.fillWidth: true
                spacing: Appearance.spacing.space25

                SectionHeader {
                    icon: ScreenRecord.recording ? "screen_record" : "replay"
                    label: ScreenRecord.recording
                        ? Translation.tr("Recording")
                        : Translation.tr("Instant replay")
                    shape: MaterialShape.Shape.Sunny
                }

                SectionPlate {
                RowLayout {
                    Layout.fillWidth: true
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

                    ActionSlot {
                        on: root.expanded && ScreenRecord.recording
                        ActionButton {
                            symbol: ScreenRecord.recordPaused ? "play_arrow" : "pause"
                            releaseAction: () => ScreenRecord.togglePauseRecord()
                        }
                    }
                    ActionSlot {
                        on: root.expanded && ScreenRecord.recording
                        ActionButton {
                            symbol: "stop"
                            errorTone: true
                            releaseAction: () => ScreenRecord.stopRecord()
                        }
                    }
                    ActionSlot {
                        // The replay buffer's whole point: keep what just
                        // happened. Saving does not disarm it.
                        on: root.expanded && ScreenRecord.replaying
                        ActionButton {
                            symbol: "save"
                            symbolColor: Appearance.colors.colPrimary
                            releaseAction: () => ScreenRecord.saveReplay()
                        }
                    }
                    ActionSlot {
                        on: root.expanded && ScreenRecord.replaying
                        ActionButton {
                            symbol: "stop"
                            errorTone: true
                            releaseAction: () => ScreenRecord.toggleReplay()
                        }
                    }
                }
                }
            }

            Reveal {
                shown: root.expanded

                SectionHeader {
                    icon: "key"
                    label: Translation.tr("Granted permissions")
                    shape: MaterialShape.Shape.Gem
                }

                SectionPlate {
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
                                    ActionSlot {
                                        on: root.expanded
                                        ActionButton {
                                            symbol: "block"
                                            errorTone: true
                                            releaseAction: () => CaptureControl.revokePermission(
                                                permissionEntry.modelData.id, permissionAppRow.modelData.app)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        // Honest about its own reach: only portal-mediated apps
                        // have anything to revoke, so an empty list is the
                        // normal state on a system without sandboxed apps - not
                        // a failure, and not a claim that nothing is recording.
                        visible: CaptureControl.permissions.every(p => p.apps.length === 0)
                        Layout.fillWidth: true
                        text: Translation.tr("Nothing granted through the desktop portal. Apps that open the device directly do not appear here.")
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: 0.55
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }
            }
        }
    }

    // Read the store when the controls are actually opened, not on every hover.
    onExpandedChanged: {
        if (root.expanded) CaptureControl.refreshPermissions();
        // Hand the card over to the content for the length of the change, and
        // take it back afterwards so entering and leaving the card still
        // animate the way every other bar popup does.
        root.contentDrivesSize = true;
        depthSettle.restart();
    }

    property Timer depthSettle: Timer {
        interval: root.revealDuration + 60
        onTriggered: root.contentDrivesSize = false
    }
}
