pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import "../../common/plugins/bundled/docker" as DockerPackage

// Native bar adapter for the bundled Docker manager. Its geometry follows the
// same content-driven contract as WeatherBar so BarGroup remains the sole
// owner of the surrounding layout size.
MouseArea {
    id: root

    property bool vertical: Config.options.bar.vertical
    property bool popupOpen: false
    property bool useOutsideClickGrab: true
    readonly property real horizontalPadding: Appearance.spacing.space100

    implicitWidth: root.vertical
        ? (contentLoader.item?.implicitWidth ?? 32)
        : (contentLoader.item?.implicitWidth ?? 0) + root.horizontalPadding * 2
    implicitHeight: root.vertical
        ? (contentLoader.item?.implicitHeight ?? 0)
        : Appearance.sizes.barHeight
    acceptedButtons: Qt.LeftButton
    hoverEnabled: false
    cursorShape: Qt.PointingHandCursor

    onClicked: {
        root.popupOpen = !root.popupOpen;
        if (root.popupOpen) DockerPackage.DockerService.refresh();
    }
    onPopupOpenChanged: {
        if (root.popupOpen) {
            focusArm.attempts = 0;
            focusArm.restart();
        } else {
            focusArm.stop();
            popupFocus.active = false;
            popupFocus.windows = [];
        }
    }

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.vertical ? verticalContent : horizontalContent
    }

    Component {
        id: horizontalContent
        RowLayout {
            spacing: Appearance.spacing.space100

            StyledText {
                text: `${DockerPackage.DockerService.runningCount}/${DockerPackage.DockerService.totalCount}`
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: DockerPackage.DockerService.dockerAvailable
                    ? Appearance.colors.colPrimary : Appearance.colors.colError
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                implicitWidth: 25
                implicitHeight: 25
                radius: Appearance.rounding.full
                color: DockerPackage.DockerService.dockerAvailable
                    ? Appearance.colors.colPrimary : Appearance.colors.colError

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 0
                    text: "deployed_code"
                    iconSize: Appearance.font.pixelSize.normal
                    color: DockerPackage.DockerService.dockerAvailable
                        ? Appearance.colors.colOnPrimary : Appearance.colors.colOnError
                }
            }
        }
    }

    Component {
        id: verticalContent
        ColumnLayout {
            spacing: Appearance.spacing.space25

            Rectangle {
                implicitWidth: 25
                implicitHeight: 25
                radius: Appearance.rounding.full
                color: DockerPackage.DockerService.dockerAvailable
                    ? Appearance.colors.colPrimary : Appearance.colors.colError
                Layout.alignment: Qt.AlignHCenter

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 0
                    text: "deployed_code"
                    iconSize: Appearance.font.pixelSize.normal
                    color: DockerPackage.DockerService.dockerAvailable
                        ? Appearance.colors.colOnPrimary : Appearance.colors.colOnError
                }
            }

            StyledText {
                text: DockerPackage.DockerService.runningCount
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: DockerPackage.DockerService.dockerAvailable
                    ? Appearance.colors.colPrimary : Appearance.colors.colError
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    Loader {
        id: popupLoader
        active: root.popupOpen
        sourceComponent: DockerPackage.DockerPopup {
            pinnedOpen: true
            // StyledPopup uses its target for screen-relative positioning.
            // Hover remains disabled on the MouseArea, so this is click-only.
            hoverTarget: root
            onPinnedOpenChanged: {
                if (!pinnedOpen) root.popupOpen = false;
            }
        }
    }

    Timer {
        id: focusArm
        property int attempts: 0
        interval: 16
        repeat: true
        onTriggered: {
            const popupWindow = popupLoader.item?.item;
            if (!root.popupOpen || !root.useOutsideClickGrab || attempts++ >= 30) {
                stop();
                return;
            }
            if (!popupWindow) return;
            popupFocus.windows = [root.QsWindow?.window, popupWindow].filter(window => window);
            popupFocus.active = true;
            stop();
        }
    }

    HyprlandFocusGrab {
        id: popupFocus
        active: false
        windows: []
        onCleared: root.popupOpen = false
    }

}
