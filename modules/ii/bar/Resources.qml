import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool vertical: false
    property bool alwaysShowAllResources: false
    property bool isMaterial: Config.options.bar.cornerStyle === 3

    implicitWidth:  vertical ? (colLoader.item?.implicitWidth - 10 ?? 0) : (rowLoader.item?.implicitWidth  ?? 0) + 12
    implicitHeight: vertical ? (colLoader.item?.implicitHeight ?? 0) + (isMaterial ? 15 : 10) : Appearance.sizes.barHeight - 8
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    Rectangle {
        anchors.fill: parent
        color: root.isMaterial ? Appearance.colors.colTertiaryContainer : "transparent"
        radius: Appearance.rounding.full

        Loader {
            id: rowLoader
            active: !root.vertical
            visible: active
            anchors.centerIn: parent 
            anchors.leftMargin: 2
            anchors.rightMargin: 4
            sourceComponent: RowLayout {
                spacing: 0
                Resource {
                    iconName: "memory"
                    shown: Config.options.bar.resources.alwaysShowRam
                    percentage: ResourceUsage.memoryUsedPercentage
                    warningThreshold: Config.options.bar.resources.memoryWarningThreshold
                }
                Resource {
                    iconName: "planner_review"
                    shown: Config.options.bar.resources.alwaysShowCpu
                    percentage: ResourceUsage.cpuUsage
                    Layout.leftMargin: shown ? 6 : 0
                    warningThreshold: Config.options.bar.resources.cpuWarningThreshold
                }
                Resource {
                    iconName: "thermostat"
                    shown: Config.options.bar.resources.alwaysShowCpuTemp
                    percentage: ResourceUsage.cpuTemp / 100
                    Layout.leftMargin: shown ? 6 : 0
                }
                Resource {
                    iconName: "hard_drive"
                    shown: Config.options.bar.resources.alwaysShowDisk
                    percentage: ResourceUsage.diskUsedPercentage
                    Layout.leftMargin: shown ? 6 : 0
                }
                Resource {
                    iconName: "swap_horiz"
                    shown: Config.options.bar.resources.alwaysShowSwap
                    percentage: ResourceUsage.swapUsedPercentage
                    Layout.leftMargin: shown ? 6 : 0
                    warningThreshold: Config.options.bar.resources.swapWarningThreshold
                }
            }
        }

        Loader {
            id: colLoader
            active: root.vertical
            visible: active
            anchors.centerIn: parent 
            sourceComponent: ColumnLayout {
                spacing: 7
                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "memory"
                    vertical: true
                    visible: Config.options.bar.resources.alwaysShowRam
                    percentage: ResourceUsage.memoryUsedPercentage
                    warningThreshold: Config.options.bar.resources.memoryWarningThreshold
                }
                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "planner_review"
                    vertical: true
                    visible: Config.options.bar.resources.alwaysShowCpu
                    percentage: ResourceUsage.cpuUsage
                    warningThreshold: Config.options.bar.resources.cpuWarningThreshold
                }
                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "thermostat"
                    vertical: true
                    visible: Config.options.bar.resources.alwaysShowCpuTemp
                    percentage: ResourceUsage.cpuTemp / 100
                }
                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "hard_drive"
                    vertical: true
                    visible: Config.options.bar.resources.alwaysShowDisk
                    percentage: ResourceUsage.diskUsedPercentage
                }
                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "swap_horiz"
                    vertical: true
                    visible: Config.options.bar.resources.alwaysShowSwap
                    percentage: ResourceUsage.swapUsedPercentage
                    warningThreshold: Config.options.bar.resources.swapWarningThreshold
                }
            }
        }

        ResourcesPopup {
            hoverTarget: root
        }
    }
}