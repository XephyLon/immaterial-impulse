pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import "."

// Follow WeatherBar's proven geometry and Material treatment: the value comes
// first and a compact primary-colored circular icon closes the horizontal row.
MouseArea {
    id: root

    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    property bool popupOpen: false
    property bool useOutsideClickGrab: true

    // This bar entry owns a fixed, bounded canvas. Never derive the host size
    // from a child Layout: the surrounding BarGroup Loader also derives its
    // width from this item, which otherwise collapses the visual to zero.
    implicitWidth: root.vertical ? 32 : 64
    implicitHeight: root.vertical ? 54 : Appearance.sizes.barHeight
    width: implicitWidth
    height: implicitHeight

    // Preserve the bar's native MouseArea sizing/hit contract, but never track
    // pointer entry. Only a real left-button click can instantiate the manager.
    acceptedButtons: Qt.LeftButton
    hoverEnabled: false
    cursorShape: Qt.PointingHandCursor
    onClicked: {
        root.popupOpen = !root.popupOpen;
        if (root.popupOpen) DockerService.refresh();
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

    Item {
        id: rowContent
        visible: !root.vertical
        anchors.fill: parent

        StyledText {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: `${DockerService.runningCount}/${DockerService.totalCount}`
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.isMaterial && DockerService.dockerAvailable
                ? Appearance.colors.colPrimary
                : DockerService.dockerAvailable
                    ? Appearance.colors.colOnLayer1 : Appearance.colors.colError
        }

        Rectangle {
            width: 25
            height: 25
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            radius: Appearance.rounding.full
            color: DockerService.dockerAvailable
                ? Appearance.colors.colPrimary : Appearance.colors.colError

            MaterialSymbol {
                anchors.centerIn: parent
                fill: 0
                text: "deployed_code"
                iconSize: Appearance.font.pixelSize.normal
                color: DockerService.dockerAvailable
                    ? Appearance.colors.colOnPrimary : Appearance.colors.colOnError
            }
        }
    }

    Item {
        id: colContent
        visible: root.vertical
        anchors.fill: parent

        Rectangle {
            width: 25
            height: 25
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            radius: Appearance.rounding.full
            color: DockerService.dockerAvailable
                ? Appearance.colors.colPrimary : Appearance.colors.colError

            MaterialSymbol {
                anchors.centerIn: parent
                fill: 0
                text: "deployed_code"
                iconSize: Appearance.font.pixelSize.normal
                color: DockerService.dockerAvailable
                    ? Appearance.colors.colOnPrimary : Appearance.colors.colOnError
            }
        }

        StyledText {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: DockerService.runningCount
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.isMaterial && DockerService.dockerAvailable
                ? Appearance.colors.colPrimary
                : DockerService.dockerAvailable
                    ? Appearance.colors.colOnLayer1 : Appearance.colors.colError
        }
    }

    Loader {
        id: popupLoader
        active: root.popupOpen
        sourceComponent: DockerPopup {
            pinnedOpen: true
            // Needed for popup positioning; root does not track hover.
            hoverTarget: root
            onPinnedOpenChanged: {
                if (!pinnedOpen) root.popupOpen = false;
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

}
