import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Hover popup for the privacy indicator: lists which devices are in use and by
// which app(s). Each app gets its own wrapped line, so several apps sharing one
// device (e.g. two apps recording the mic) all show cleanly.
StyledPopup {
    id: root
    morph: true
    contentPadding: Appearance.spacing.space150

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

    Item {
        implicitWidth: 260
        implicitHeight: column.implicitHeight

        ColumnLayout {
            id: column
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            spacing: Appearance.spacing.space100

            StyledText {
                Layout.leftMargin: Appearance.spacing.space50
                text: Translation.tr("Privacy")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colError
            }

            DeviceSection {
                visible: MediaCapture.micActive
                icon: "mic"
                label: Translation.tr("Microphone")
                entries: MediaCapture.micApps.length > 0
                    ? MediaCapture.micApps
                    : [Translation.tr("In use")]
            }

            DeviceSection {
                visible: MediaCapture.cameraActive
                icon: "videocam"
                label: Translation.tr("Camera")
                entries: MediaCapture.cameraApps.length > 0
                    ? MediaCapture.cameraApps
                    : [Translation.tr("In use")]
            }

            DeviceSection {
                visible: MediaCapture.screencastActive
                icon: "screen_share"
                label: Translation.tr("Screen")
                entries: [Translation.tr("Shared or recorded")]
            }

            DeviceSection {
                visible: ScreenRecord.recording
                icon: "screen_record"
                label: Translation.tr("Recording")
                entries: [ScreenRecord.recordPaused
                    ? Translation.tr("Paused")
                    : Translation.tr("Recording the screen")]
            }

            DeviceSection {
                visible: ScreenRecord.replaying
                icon: "replay"
                label: Translation.tr("Instant replay")
                entries: [Translation.tr("Buffering the last moments")]
            }
        }
    }
}
