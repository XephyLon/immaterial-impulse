import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    forceWidth: true
    bottomContentPadding: 35

    function runSystemUpdate() {
        Quickshell.execDetached([
            "kitty", "--hold",
            "fish", "-i", "-l", "-c",
            "yay -Syu --combinedupgrade=false"
        ])
        Qt.callLater(() => GlobalStates.settingsOpen = false)
    }

    function runUpdateDots() {
        Quickshell.execDetached([
            "kitty", "--hold",
            "bash", "-c",
            "killall qs; sleep 0.5; cd ~/.config/quickshell/ && rm -rf end4-pC && git clone https://github.com/pctrade/end4-pC.git && nohup qs -c end4-pC > /tmp/qs.log 2>&1 &"
        ])
        Qt.callLater(() => GlobalStates.settingsOpen = false)
    }
    
    RowLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 50
        spacing: Appearance.spacing.large

        IconImage {
            implicitWidth: 134
            implicitHeight: 134
            source: Quickshell.iconPath(SystemInfo.logo)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.verysmall

            StyledText {
                text: SystemInfo.distroName
                font.pixelSize: Appearance.font.pixelSize.hugeass
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }

            StyledText {
                text: "Kernel " + (SystemInfo.kernelVersion || "Loading...")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            Item {
                implicitWidth: colorRow.implicitWidth
                implicitHeight: 24

                Row {
                    id: colorRow
                    spacing: -8

                    Repeater {
                        model: [
                            Appearance.m3colors.m3primary,
                            Appearance.m3colors.m3secondary,
                            Appearance.m3colors.m3tertiary,
                            Appearance.m3colors.m3error,
                            Appearance.m3colors.m3primaryContainer,
                            Appearance.m3colors.m3secondaryContainer,
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: 24
                            height: 24
                            radius: width / 2
                            color: modelData
                            z: index
                            border.width: Appearance.borderWidth.emphasis
                            border.color: Appearance.colors.colLayer1
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            AboutCard {
                icon: "planner_review"
                label: "CPU"
                value: SystemInfo.cpu || "Loading..."
                Layout.fillWidth: true
            }

            AboutCard {
                icon: "monitor"
                label: "GPU"
                value: SystemInfo.gpu || "N/A"
                Layout.fillWidth: true
            }
        }

        GridLayout {
            columns: 2
            Layout.fillWidth: true
            rowSpacing: 8
            columnSpacing: 8

            AboutCard {
                icon: "memory"
                label: "Memory"
                value: SystemInfo.memory || "Loading..."
                Layout.fillWidth: true
            }

            AboutCard {
                icon: "storage"
                label: "Disk"
                value: SystemInfo.disk || "Loading..."
                Layout.fillWidth: true
            }

            AboutCard {
                icon: "terminal"
                label: "Shell"
                value: SystemInfo.shell || "Loading..."
                Layout.fillWidth: true
            }

            AboutCard {
                icon: "package_2"
                label: "Packages"
                value: SystemInfo.packages || "Loading..."
                Layout.fillWidth: true
            }

            AboutCard {
                icon: "update"
                label: "Updates"
                value: Updates.checking ? "Checking..." : (Updates.count === 0 ? "Up to date" : `${Updates.count}`)
                Layout.fillWidth: true
            }

            AboutCard {
                icon: "timelapse"
                label: "Uptime"
                value: DateTime.uptime || "Loading..."
                Layout.fillWidth: true
            }
        }
    }

    RowLayout {
        spacing: Appearance.spacing.small
        Layout.alignment: Qt.AlignRight

        RippleButton {
            buttonText: Translation.tr("Update System")
            buttonRadius: Appearance.rounding.full
            border: true
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            Layout.preferredHeight: 44
            downAction: () => runSystemUpdate()

            contentItem: StyledText {
                text: parent.buttonText
                horizontalAlignment: Text.AlignHCenter
                leftPadding: Appearance.spacing.normal
                rightPadding: Appearance.spacing.normal
            }
        }

        RippleButton {
            buttonText: Translation.tr("Update Dots")
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            Layout.preferredHeight: 44
            downAction: () => runUpdateDots()

            contentItem: StyledText {
                text: parent.buttonText
                horizontalAlignment: Text.AlignHCenter
                leftPadding: Appearance.spacing.normal
                rightPadding: Appearance.spacing.normal
            }
        }
    }
}