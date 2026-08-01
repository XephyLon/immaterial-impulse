import qs.modules.common
import qs.modules.common.functions as Functions
import qs.services
import "../services"
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Android-style indicator for screen recording.
 * Shows a primary-colored pill with a timer when active.
 */
Item {
    id: root

    function formatDuration(totalSeconds) {
        const minutes = Math.floor(totalSeconds / 60);
        const seconds = Math.max(0, totalSeconds % 60);
        return `${minutes}:${String(seconds).padStart(2, "0")}`;
    }
    visible: ScreenRecord.active
    implicitWidth: mainContainer.width
    implicitHeight: 24 * Appearance.effectiveScale

    Rectangle {
        id: mainContainer
        anchors.verticalCenter: parent.verticalCenter
        height: 20 * Appearance.effectiveScale
        width: contentLayout.implicitWidth + (12 * Appearance.effectiveScale)
        radius: height / 2
        color: Appearance.m3colors.m3primary
        clip: true

        RowLayout {
            id: contentLayout
            anchors.centerIn: parent
            spacing: 6 * Appearance.effectiveScale

            MaterialSymbol {
                id: recordIcon
                text: "videocam"
                iconSize: 14 * Appearance.effectiveScale
                color: Appearance.m3colors.m3onPrimary
                fill: 1
            }

            StyledText {
                text: root.formatDuration(ScreenRecord.seconds)
                font.pixelSize: Math.round(12 * Appearance.effectiveScale)
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3onPrimary
            }
        }
    }

    opacity: visible ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 300 }
    }
}
