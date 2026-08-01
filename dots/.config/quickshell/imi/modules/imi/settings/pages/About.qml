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
    id: root
    forceWidth: true
    bottomContentPadding: 35

    // Suite version, read from the VERSION file shipped in the shell dir (it
    // deploys with the config and is present in the repo checkout too).
    property string appVersion: "dev"
    FileView {
        id: versionFile
        path: Qt.resolvedUrl(Quickshell.shellPath("VERSION"))
        onLoaded: {
            const v = (versionFile.text() || "").trim();
            if (v.length > 0) root.appVersion = v;
        }
    }

    // "What's new": the changelog from the suite checkout get.sh updates.
    // Bounded to the newest two sections (Unreleased + latest release).
    property string changelogText: ""
    property bool changelogExpanded: false
    readonly property var changelogParsed: {
        if (!root.changelogText) return { title: "", body: "" };
        const lines = root.changelogText.split("\n");
        const starts = [];
        for (let i = 0; i < lines.length; i++)
            if (lines[i].startsWith("## ")) starts.push(i);
        if (starts.length === 0) return { title: "", body: "" };
        const end = starts.length > 2 ? starts[2] : lines.length;
        return {
            title: lines[starts[0]].replace(/^## /, "").replace(/[\[\]]/g, ""),
            body: lines.slice(starts[0] + 1, end).join("\n").trim()
        };
    }
    FileView {
        id: changelogFile
        path: `${Directories.suiteSrc}/CHANGELOG.md`
        onLoaded: root.changelogText = changelogFile.text() || ""
    }

    function runSystemUpdate() {
        Quickshell.execDetached([
            "kitty", "--hold",
            "fish", "-i", "-l", "-c",
            "yay -Syu --combinedupgrade=false"
        ])
        Qt.callLater(() => GlobalStates.settingsOpen = false)
    }

    function runUpdateDots() {
        // Update = re-run the installer. Fetch get.sh (portable download-then-run
        // form so it works under the fish login shell too) — it updates the local
        // suite checkout and launches setup. The installer is idempotent, so it
        // doubles as the updater; a terminal is opened so the user can follow /
        // answer the menu. Replaces the old self-reinstall that cloned into
        // ~/.config/quickshell and relaunched `qs -c end4-pC` (invalid now that
        // the repo is a full suite rather than a drop-in config dir).
        Quickshell.execDetached([
            "kitty", "--hold",
            "fish", "-i", "-l", "-c",
            "curl -fsSL https://raw.githubusercontent.com/XephyLon/immaterial-impulse/main/get.sh -o /tmp/imi-get.sh && bash /tmp/imi-get.sh"
        ])
        Qt.callLater(() => GlobalStates.settingsOpen = false)
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 156 
        Layout.topMargin: Appearance.spacing.space450
        Layout.leftMargin: Appearance.spacing.space200
        Layout.rightMargin: Appearance.spacing.space200

        radius: 24
        color: Appearance.colors.colLayer1

        RowLayout {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Appearance.spacing.space300
            spacing: Appearance.spacing.space300

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 110
                implicitHeight: 110
                radius: 20
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)

                IconImage {
                    anchors.centerIn: parent
                    implicitWidth: 72
                    implicitHeight: 72
                    source: Quickshell.iconPath(SystemInfo.logo)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Appearance.spacing.space50

                StyledText {
                    Layout.fillWidth: true
                    text: SystemInfo.distroName
                    font.pixelSize: Appearance.font.pixelSize.hugeass
                    font.weight: Font.ExtraBold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Kernel " + (SystemInfo.kernelVersion || "Loading...")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Immaterial Impulse v" + root.appVersion
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                Row {
                    id: colorRow
                    spacing: -Appearance.spacing.space100

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
                            width: 28
                            height: 28
                            radius: width / 2
                            color: modelData
                            z: index
                            border.width: Appearance.borderWidth.emphasis
                            border.color: Appearance.colors.colLayer1
                        }
                    }
                }
            }
            RowLayout {
                // Anchors on a layout-managed item are undefined behavior;
                // alignment expresses the same bottom-right pin.
                Layout.alignment: Qt.AlignRight | Qt.AlignBottom
                spacing: Appearance.spacing.space100
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
                        leftPadding: Appearance.spacing.space150
                        rightPadding: Appearance.spacing.space150
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space100

        RowLayout { //This is not in the grid because I was planning to do something else.
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            AboutCard {
                icon: "planner_review"
                iconShape: MaterialShape.Shape.Pentagon
                label: "CPU"
                value: SystemInfo.cpu || "Loading..."
                Layout.fillWidth: true
            }

            AboutCard {
                icon: "monitor"
                iconShape: MaterialShape.Shape.ClamShell
                label: "GPU"
                value: SystemInfo.gpu || "N/A"
                Layout.fillWidth: true
            }
        }

        GridLayout {
            columns: 2
            Layout.fillWidth: true
            rowSpacing: Appearance.spacing.space100
            columnSpacing: Appearance.spacing.space100

            AboutCard {
                icon: "memory"
                label: "Memory"
                value: SystemInfo.memory || "Loading..."
                Layout.fillWidth: true
            }

            AboutCard {
                icon: "storage"
                iconShape: MaterialShape.Shape.Cookie6Sided
                label: "Disk"
                value: SystemInfo.disk || "Loading..."
                Layout.fillWidth: true
            }

            AboutCard {
                icon: "terminal"
                label: "Shell"
                iconShape: MaterialShape.Shape.Gem
                value: SystemInfo.shell || "Loading..."
                Layout.fillWidth: true
            }

            AboutCard {
                icon: "package_2"
                label: "Packages"
                iconShape: MaterialShape.Shape.Sunny
                value: SystemInfo.packages || "Loading..."
                Layout.fillWidth: true
            }

            AboutCard {
                icon: "update"
                label: "Updates"
                iconShape: MaterialShape.Shape.Cookie9Sided
                value: Updates.checking ? "Checking..." : (Updates.count === 0 ? "Up to date" : `${Updates.count}`)
                Layout.fillWidth: true
                clickAction: () => {
                    runSystemUpdate()
                }
            }

            AboutCard {
                icon: "timelapse"
                label: "Uptime"
                iconShape: MaterialShape.Shape.Cookie12Sided
                value: DateTime.uptime || "Loading..."
                Layout.fillWidth: true
            }
        }
    }

    Rectangle {
        visible: root.changelogParsed.body !== ""
        Layout.fillWidth: true
        Layout.topMargin: Appearance.spacing.space200
        Layout.leftMargin: Appearance.spacing.space200
        Layout.rightMargin: Appearance.spacing.space200
        Layout.preferredHeight: whatsNewColumn.implicitHeight + Appearance.spacing.space300 * 2

        radius: 24
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: whatsNewColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: Appearance.spacing.space300
            }
            spacing: Appearance.spacing.space200

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space200

                MaterialSymbol {
                    text: "new_releases"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: Translation.tr("What's new")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        text: root.changelogParsed.title
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    implicitHeight: 36
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: Qt.openUrlExternally("https://github.com/XephyLon/immaterial-impulse/blob/main/CHANGELOG.md")
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: Appearance.spacing.space200
                        rightPadding: Appearance.spacing.space200
                        text: Translation.tr("Full changelog")
                        color: Appearance.colors.colOnLayer2
                    }
                }

                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.changelogExpanded = !root.changelogExpanded
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "expand_more"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer2
                        rotation: root.changelogExpanded ? 180 : 0
                        Behavior on rotation {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }
            }

            StyledText {
                visible: root.changelogExpanded
                Layout.fillWidth: true
                text: root.changelogParsed.body
                textFormat: Text.MarkdownText
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                onLinkActivated: link => Qt.openUrlExternally(link)
                PointingHandLinkHover {}
            }
        }
    }
}
