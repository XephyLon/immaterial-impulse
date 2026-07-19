pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import "../../common/plugins/bundled/docker" as DockerPackage

// Native bar adapter for the bundled Docker manager. Keep the visible surface
// in the bar module: passing package-root geometry through another component
// boundary repeatedly collapsed its scene-graph content to a one-pixel edge.
MouseArea {
    id: root

    property bool vertical: Config.options.bar.vertical
    property bool popupOpen: false

    implicitWidth: root.vertical ? 32 : 64
    implicitHeight: root.vertical ? 54 : Appearance.sizes.barHeight
    width: implicitWidth
    height: implicitHeight
    acceptedButtons: Qt.LeftButton
    hoverEnabled: false

    onClicked: {
        root.popupOpen = !root.popupOpen;
        if (root.popupOpen) DockerPackage.DockerService.refresh();
    }

    StyledText {
        visible: !root.vertical
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: `${DockerPackage.DockerService.runningCount}/${DockerPackage.DockerService.totalCount}`
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.DemiBold
        color: DockerPackage.DockerService.dockerAvailable
            ? Appearance.colors.colPrimary : Appearance.colors.colError
    }

    Rectangle {
        width: 25
        height: 25
        anchors.right: root.vertical ? undefined : parent.right
        anchors.top: root.vertical ? parent.top : undefined
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
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

    StyledText {
        visible: root.vertical
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        text: DockerPackage.DockerService.runningCount
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.DemiBold
        color: DockerPackage.DockerService.dockerAvailable
            ? Appearance.colors.colPrimary : Appearance.colors.colError
    }

    Loader {
        active: root.popupOpen
        sourceComponent: DockerPackage.DockerPopup {
            pinnedOpen: true
            hoverTarget: null
            onPinnedOpenChanged: {
                if (!pinnedOpen) root.popupOpen = false;
            }
        }
    }
}
