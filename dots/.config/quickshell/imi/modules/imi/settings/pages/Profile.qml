import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs
import qs.services
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models

ContentPage {
    id: page
    property string descriptionMode: {
        if (Config.options.profile.descriptionText === "::uptime::") return "uptime"
        return "distro"
    }
    property string hostnameInput: SystemInfo.hostname

    FolderListModel {
        id: avatarFolderModel
        folder: Config.options.profile.avatarPath !== "" ? Qt.resolvedUrl(Config.options.profile.avatarPath) : ""
        showDirs: false
        nameFilters: ["*.png", "*.svg", "*.jpg", "*.jpeg", "*.webp"]
    }

    Process {
        id: hostnameSetProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                SystemInfo.refreshHostname()
            }
        }
    }

    function applyHostname() {
        const newName = page.hostnameInput.trim()
        if (newName.length === 0 || newName === SystemInfo.hostname) return
        hostnameSetProc.command = ["hostnamectl", "set-hostname", newName]
        hostnameSetProc.running = true
    }

    Connections {
        target: SystemInfo
        function onHostnameChanged() {
            // Keep the editable draft in sync after hostnamectl completes.
            page.hostnameInput = SystemInfo.hostname
        }
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Appearance.spacing.space250

        ContentSection {
            icon: "person"
            shape: MaterialShape.Shape.Circle
            title: Translation.tr("Avatar")

            GroupedList {
                ConfigTextArea {
                    id: avatarField
                    Layout.fillWidth: true
                    buttonIcon: "folder_open"
                    text: Translation.tr("Avatar path")
                    placeholderText: Translation.tr("Leave empty to use ~/.face, e.g. /home/youruser/Pictures/avatar")
                    value: Config.options.profile.avatarPath
                    onValueChanged: {
                        avatarDebounceTimer.restart()
                    }

                    Timer {
                        id: avatarDebounceTimer
                        interval: 1000
                        repeat: false
                        onTriggered: {
                            Config.options.profile.avatarPath = avatarField.value
                        }
                    }

                    confirmButtonVisible: Config.options.profile.avatarPath !== ""
                    confirmButtonIcon: "add"
                    onConfirmClicked: {
                        GlobalStates.settingsOpen = false
                        if (Config.options.profile.avatarPath !== "") {
                            Quickshell.execDetached(["dolphin", Config.options.profile.avatarPath])
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    // A height of its own while the placeholder is up: the
                    // shared placeholder FILLS what it is given, so taking
                    // this item's height from it would be a loop.
                    implicitHeight: Config.options.profile.avatarPath === "" ? 200 : avatarFlow.implicitHeight

                    Flow {
                        id: avatarFlow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Appearance.spacing.space100
                        anchors.rightMargin: Appearance.spacing.space100
                        spacing: Appearance.spacing.space100

                        Repeater {
                            model: avatarFolderModel
                            // A button, not a bare plate with a MouseArea: the
                            // cards are picked, so they hover, press and morph
                            // like every other selection card in Settings.
                            delegate: RippleButton {
                                id: avatarCard
                                required property string fileName
                                required property string filePath
                                padding: 0
                                implicitWidth: 64
                                implicitHeight: 64
                                buttonRadius: width / 2
                                // No radius morph on press: the picture is
                                // masked to a circle of its own, so a plate
                                // that squares under it shows its corners.
                                buttonRadiusPressed: avatarCard.buttonRadius
                                colBackground: Appearance.colors.colLayer2
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                // The picture is the card, so the selected card
                                // keeps the same plate and says so with the
                                // check badge below rather than a tone nobody
                                // can see under the image.
                                toggled: avatarCard.isSelected
                                colBackgroundToggled: Appearance.colors.colLayer2
                                colBackgroundToggledHover: Appearance.colors.colLayer2Hover
                                colRippleToggled: Appearance.colors.colLayer2Active

                                property bool isSelected: FileUtils.trimFileProtocol(avatarCard.filePath.toString()) === Config.options.profile.avatarPicture

                                onClicked: Config.options.profile.avatarPicture = FileUtils.trimFileProtocol(avatarCard.filePath.toString())

                                contentItem: Item {
                                    Image {
                                        id: avatarImage
                                        anchors.fill: parent
                                        source: avatarCard.filePath
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize.width: avatarImage.width * 2
                                        sourceSize.height: avatarImage.height * 2
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: 64
                                                height: width
                                                radius: width / 2
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: avatarCard.isSelected
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.rightMargin: Appearance.spacing.space25
                                        anchors.bottomMargin: Appearance.spacing.space25
                                        width: 20
                                        height: width
                                        radius: width / 2
                                        color: Appearance.colors.colPrimary

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "check"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnPrimary
                                        }
                                    }
                                }
                            }
                        }
                    }

                    PagePlaceholder {
                        id: placeholderCol
                        shown: Config.options.profile.avatarPath === ""
                        z: 1
                        icon: "image"
                        shape: MaterialShape.Shape.Circle
                        title: Translation.tr("No avatars yet")
                        description: Translation.tr("Pick a folder above to see avatars here")
                        descriptionHorizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Identity")

                GroupedList {
                    ConfigTextArea {
                        id: displayNameField
                        buttonIcon: "badge"
                        placeholderText: SystemInfo.username
                        text: Translation.tr("Display name")
                        value: Config.options.profile.displayName

                        Timer {
                            id: displayNameDebounceTimer
                            interval: 800
                            running: false
                            onTriggered: {
                                Config.options.profile.displayName = displayNameField.value
                            }
                        }
                        onValueChanged: displayNameDebounceTimer.restart()
                    }

                    ConfigTextArea {
                        id: hostnameField
                        Layout.fillWidth: true
                        buttonIcon: "dns"
                        placeholderText: SystemInfo.hostname
                        text: Translation.tr("Hostname")
                        description: Translation.tr("Requires authentication to change")
                        value: page.hostnameInput
                        onValueChanged: page.hostnameInput = value

                        confirmButtonVisible: page.hostnameInput.trim() !== "" && page.hostnameInput.trim() !== SystemInfo.hostname
                        onConfirmClicked: {
                            page.applyHostname();
                        }
                    }

                    ConfigSelectionArray {
                        text: Translation.tr("Description text")
                        icon: "subtitles"
                        currentValue: page.descriptionMode
                        onSelected: newValue => {
                            page.descriptionMode = newValue
                            if (newValue === "distro") Config.options.profile.descriptionText = "::distro::"
                            if (newValue === "uptime") Config.options.profile.descriptionText = "::uptime::"
                        }
                        options: [
                            { displayName: Translation.tr("Distro"), icon: "deployed_code", value: "distro" },
                            { displayName: Translation.tr("Uptime"), icon: "timelapse",     value: "uptime" },
                        ]
                    }
                }
            }
        }

        ContentSection {
            icon: "wall_art"
            shape: MaterialShape.Shape.Pentagon
            title: Translation.tr("Presets")

            GroupedList {
                ConfigTextArea {
                    id: presetNameField
                    Layout.fillWidth: true
                    fieldWidth: 300
                    buttonIcon: "newsmode"
                    text: Translation.tr("New")
                    placeholderText: Translation.tr("Name, description (optional)")

                    confirmButtonVisible: presetNameField.value.trim() !== ""
                    confirmButtonIcon: "save"
                    onConfirmClicked: {
                        Presets.save(presetNameField.value)
                        presetNameField.value = ""
                    }
                }
            }

            // The shared placeholder fills and centres itself in what it is
            // given, so in this column it gets an item with its own height.
            Item {
                Layout.fillWidth: true
                Layout.topMargin: Appearance.spacing.space200
                implicitHeight: noPresetsPlaceholder.visible ? 200 : 0

                PagePlaceholder {
                    id: noPresetsPlaceholder
                    shown: Presets.folderModel.count === 0
                    icon: "bookmark_add"
                    shape: MaterialShape.Shape.Pentagon
                    title: Translation.tr("No presets yet")
                    description: Translation.tr("Name one above to save the current look.")
                    descriptionHorizontalAlignment: Text.AlignHCenter
                }
            }

            Flow {
                Layout.topMargin: Appearance.spacing.space150
                Layout.fillWidth: true
                width: parent.width
                spacing: Appearance.spacing.space150
                visible: Presets.folderModel.count > 0

                Repeater {
                    model: Presets.folderModel
                    delegate: PresetsCard {
                        id: presetDelegate
                        required property string fileName
                        required property string filePath

                        property string presetName: fileName.replace(".json", "")
                        property string presetWallpaper: ""
                        // The parsed document, kept for the selective-apply
                        // dialog's group counts - parsing once here beats the
                        // dialog re-reading the file.
                        property var presetJson: null
                        property string presetDescription: ""

                        FileView {
                            path: presetDelegate.filePath
                            onLoaded: {
                                try {
                                    const data = JSON.parse(text())
                                    const engine = data?.wallpaperSelector?.wallpaperEngine
                                    const rawWallpaper = data?.background?.wallpaperPath ?? ""
                                    // Video wallpapers can't render in an Image
                                    // preview - show the generated thumbnail.
                                    const isVideo = /\.(mp4|webm|mkv|avi|mov)$/i.test(rawWallpaper)
                                    const stillWallpaper = isVideo
                                        ? (data?.background?.thumbnailPath ?? "")
                                        : rawWallpaper
                                    // activePreview, NOT activeStill. The still was
                                    // written by code the selector-only refactor
                                    // removed, so every preset saved since carries a
                                    // frozen value belonging to whatever project was
                                    // active that day - which is why several cards
                                    // rendered the same wallpaper as each other
                                    // (#103). The preview is written by
                                    // WallpaperEngine.apply() and always matches the
                                    // project the preset actually names. Presets on
                                    // disk still hold the stale key; reading the
                                    // preview instead is what makes them harmless.
                                    presetDelegate.presetWallpaper = engine?.activeProject
                                        ? (engine.activePreview || stillWallpaper || "")
                                        : stillWallpaper
                                    presetDelegate.presetDescription = data?._presetMeta?.description ?? ""
                                    presetDelegate.presetJson = data
                                } catch (e) {
                                    console.log("Failed to parse preset:", e)
                                }
                            }
                        }

                        imageSource: presetDelegate.presetWallpaper
                        title: presetDelegate.presetName
                        description: presetDelegate.presetDescription !== "" ? presetDelegate.presetDescription : Translation.tr("Saved preset")
                        onApply: () => Presets.requestApply(presetDelegate.presetName, presetDelegate.presetJson)
                        onRemove: () => Presets.remove(presetDelegate.presetName)
                        onOverwrite: () => Presets.overwrite(presetDelegate.presetName, presetDelegate.presetDescription)
                    }
                }
            }
        }
    }
}
