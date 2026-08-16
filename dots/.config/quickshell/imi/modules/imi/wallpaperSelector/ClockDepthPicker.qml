import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/clockDepth.js" as ClockDepthLogic

/**
 * Where the quality gate lives, and it is a human.
 *
 * There is no automatic check for whether a mask is good. Scoring the whole
 * library numerically ranked rectangular slabs of background ABOVE clean
 * cutouts, and even the right model produces an unusable mask about a third of
 * the time it produces one at all - so depth is not an automatic effect, it is a
 * per-wallpaper artifact the user accepts once, with segmentation proposing
 * candidates.
 *
 * Two models, because neither is a superset of the other: `isnet-anime` carries
 * most of this library and returns nothing at all on the semi-photographic
 * minority that `isnet-general-use` handles best. Both are offered; either, or
 * neither, can be chosen.
 *
 * The preview is composited the way the desktop is - the wallpaper cropped as it
 * will be, dimmed, with a clock over it, and the cutout on top - rather than
 * shown as a bare mask. A bare cutout hides the failure that matters: the depth
 * layer paints the wallpaper's own pixels back over themselves, so a wrong mask
 * costs nothing where no widget sits, and the only question is whether it is
 * right where the clock is.
 */
Item {
    id: root

    required property real screenAspect

    readonly property string wallpaper: ClockDepth.wallpaperPath
    readonly property bool busy: ClockDepth.running !== ""

    signal closeRequested()

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.normal
    }

    // The scrim swallows clicks aimed at the grid behind the picker. Everything
    // here is a real control, so unlike the depth layer itself this one WANTS
    // the input.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: {}
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space200
        spacing: Appearance.spacing.space150

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                text: "layers"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnLayer0
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("Depth for this wallpaper")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    text: ClockDepth.lastError !== ""
                        ? ClockDepth.lastError
                        : Translation.tr("Run a model, then keep the cutout only if the subject's edge looks right where your widgets sit.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ClockDepth.lastError !== ""
                        ? Appearance.m3colors.m3error
                        : Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: height / 2
                onClicked: root.closeRequested()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer0
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Appearance.spacing.space150

            Repeater {
                model: ClockDepth.models

                ColumnLayout {
                    id: candidate
                    required property string modelData

                    readonly property string maskPath: ClockDepth.candidates?.[candidate.modelData] ?? ""
                    // Absent from `candidates` and absent from `results` are
                    // different things and must read differently: the first is a
                    // model nobody has run, the second is a model that ran and
                    // found nothing. Collapsing them is how a picker ends up
                    // inviting the user to spend 4.5 seconds re-learning that
                    // there is no one in the picture.
                    readonly property bool refused: candidate.modelData in (ClockDepth.candidates ?? ({}))
                        && candidate.maskPath === ""
                    readonly property bool thisRunning: ClockDepth.running === candidate.modelData

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignTop
                    // Both columns take half the row whatever their content is
                    // wider than. Without a preferred width a RowLayout hands
                    // fillWidth children their implicit widths first, so the
                    // column whose button labels are longer gets a bigger
                    // preview - and the two cutouts are being compared.
                    Layout.preferredWidth: 1
                    spacing: Appearance.spacing.space100

                    StyledText {
                        text: candidate.modelData === "isnet-anime"
                            ? Translation.tr("Illustration")
                            : Translation.tr("Photographic")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer0
                    }

                    Item {
                        id: preview
                        Layout.fillWidth: true
                        Layout.preferredHeight: width / root.screenAspect
                        Layout.maximumHeight: 320
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1
                        }

                        Image {
                            id: previewWallpaper
                            anchors.fill: parent
                            source: root.wallpaper === "" ? "" : `file://${root.wallpaper}`
                            fillMode: Image.PreserveAspectCrop
                            cache: true
                            smooth: true
                            asynchronous: true
                            visible: false
                        }

                        // Everything that is NOT the subject, dimmed. This is
                        // the whole reason the preview is not the plain
                        // wallpaper: a soft edge is invisible against the image
                        // it was cut from, and a rectangular slab of background
                        // is only obvious once the rest is darker than it.
                        Image {
                            anchors.fill: parent
                            source: previewWallpaper.source
                            fillMode: Image.PreserveAspectCrop
                            cache: true
                            smooth: true
                            asynchronous: true
                            opacity: 0.35
                        }

                        StyledText {
                            id: previewClock
                            anchors.centerIn: parent
                            text: DateTime.time
                            font.pixelSize: Math.max(24, preview.height * 0.34)
                            font.family: Config.options.background.widgets.clock.digital.font.family
                            color: Appearance.colors.colOnLayer0
                        }

                        Item {
                            id: previewMaskSurface
                            anchors.fill: parent
                            visible: false
                            clip: true

                            Image {
                                id: previewMask
                                readonly property var coverRect: ClockDepthLogic.coverRect(
                                    previewWallpaper.implicitWidth, previewWallpaper.implicitHeight,
                                    previewMaskSurface.width, previewMaskSurface.height)
                                x: previewMask.coverRect.x
                                y: previewMask.coverRect.y
                                width: previewMask.coverRect.width
                                height: previewMask.coverRect.height
                                source: candidate.maskPath === "" ? "" : `file://${candidate.maskPath}`
                                fillMode: Image.Stretch
                                smooth: true
                                asynchronous: true
                            }
                        }

                        OpacityMask {
                            anchors.fill: parent
                            source: previewWallpaper
                            maskSource: previewMaskSurface
                            visible: candidate.maskPath !== ""
                        }

                        // Along the bottom edge rather than centred: the middle
                        // of the preview is where the clock is, and a status
                        // label printed across it is sitting on the one thing
                        // the user came here to look at.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            implicitHeight: statusLabel.implicitHeight + Appearance.spacing.space100
                            visible: candidate.maskPath === "" || candidate.thisRunning
                            color: Appearance.colors.colLayer0

                            StyledText {
                                id: statusLabel
                                anchors.centerIn: parent
                                text: candidate.thisRunning
                                    ? Translation.tr("Looking for a subject…")
                                    : candidate.refused
                                        ? Translation.tr("No subject found")
                                        : Translation.tr("Not run yet")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space100

                        DialogButton {
                            id: runButton
                            enabled: !root.busy && root.wallpaper !== ""
                            buttonText: candidate.maskPath !== "" || candidate.refused
                                ? Translation.tr("Run again")
                                : Translation.tr("Run")
                            onClicked: ClockDepth.runModel(candidate.modelData)
                        }
                        Item { Layout.fillWidth: true }
                        DialogButton {
                            id: acceptButton
                            enabled: !root.busy && candidate.maskPath !== ""
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colText: Appearance.colors.colOnPrimary
                            buttonText: Translation.tr("Use this")
                            onClicked: {
                                ClockDepth.acceptModel(candidate.modelData)
                                // Accepting a mask while the feature is switched
                                // off would put the artifact on disk and change
                                // nothing on screen, which reads as the button
                                // not working. The acceptance IS the intent.
                                Config.options.background.clockDepth.enable = true
                                root.closeRequested()
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
                text: ClockDepth.state === "accepted"
                    ? Translation.tr("This wallpaper is using a cutout.")
                    : ClockDepth.state === "declined"
                        ? Translation.tr("This wallpaper is set to no depth.")
                        : ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            DialogButton {
                id: declineButton
                enabled: !root.busy && root.wallpaper !== ""
                buttonText: Translation.tr("No depth for this wallpaper")
                onClicked: {
                    ClockDepth.declineWallpaper()
                    root.closeRequested()
                }
            }
        }
    }
}
