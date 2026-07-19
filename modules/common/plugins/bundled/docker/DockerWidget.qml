pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import "."

// Follow WeatherBar's proven geometry and Material treatment: the value comes
// first and a compact primary-colored circular icon closes the horizontal row.
MouseArea {
    id: root

    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Config.options.bar.cornerStyle === 3

    implicitWidth: root.vertical ? 32 : (contentLoader.item?.implicitWidth ?? 0)
    implicitHeight: root.vertical
        ? (contentLoader.item?.implicitHeight ?? 0)
        : Appearance.sizes.barHeight

    acceptedButtons: Qt.LeftButton
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    onClicked: {
        if (!dockerPopup.pinnedOpen) DockerService.refresh();
        dockerPopup.pinnedOpen = !dockerPopup.pinnedOpen;
    }

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.vertical ? colContent : rowContent
    }

    Component {
        id: rowContent
        RowLayout {
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                visible: !root.isMaterial
                fill: 0
                text: "deployed_code"
                iconSize: Appearance.font.pixelSize.large
                color: DockerService.dockerAvailable
                    ? Appearance.colors.colOnLayer1 : Appearance.colors.colError
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                visible: !root.isMaterial
                text: `${DockerService.runningCount}/${DockerService.totalCount}`
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                visible: root.isMaterial
                text: `${DockerService.runningCount}/${DockerService.totalCount}`
                font.pixelSize: Appearance.font.pixelSize.small
                color: DockerService.dockerAvailable
                    ? Appearance.colors.colPrimary : Appearance.colors.colError
                Layout.alignment: Qt.AlignVCenter
                leftPadding: Appearance.spacing.space100
            }

            Rectangle {
                visible: root.isMaterial
                width: 25
                height: 25
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
    }

    Component {
        id: colContent
        ColumnLayout {
            spacing: root.isMaterial ? Appearance.spacing.space25 : 0

            MaterialSymbol {
                visible: !root.isMaterial
                fill: 0
                text: "deployed_code"
                iconSize: Appearance.font.pixelSize.large
                color: DockerService.dockerAvailable
                    ? Appearance.colors.colOnLayer1 : Appearance.colors.colError
                Layout.alignment: Qt.AlignHCenter
            }

            StyledText {
                text: root.vertical
                    ? DockerService.runningCount
                    : `${DockerService.runningCount}/${DockerService.totalCount}`
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.isMaterial && DockerService.dockerAvailable
                    ? Appearance.colors.colPrimary
                    : DockerService.dockerAvailable
                        ? Appearance.colors.colOnLayer1 : Appearance.colors.colError
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: root.isMaterial ? Appearance.spacing.space50 : 0
            }

            Rectangle {
                visible: root.isMaterial
                width: 25
                height: 25
                radius: Appearance.rounding.full
                color: DockerService.dockerAvailable
                    ? Appearance.colors.colPrimary : Appearance.colors.colError
                Layout.alignment: Qt.AlignHCenter

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
    }

    DockerPopup {
        id: dockerPopup
        hoverTarget: root
    }
}
