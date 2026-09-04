import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import "./selector_places.js" as SelectorPlaces

// The selector's left sidebar. Two faces, decided by which grid is showing:
//
// - Local files: a places rail (the file-explorer shape) - folder shortcuts
//   with the directory on screen lit. The rows come from selector_places.js,
//   which is where the visibility rules and the current-place match live.
// - Wallpaper Engine: the engine's configuration (the reference app's
//   settings-sidebar shape, jagrat7/linux-wallpaper-engine): the active
//   project's card, the engine settings, and per-project overrides for
//   exactly the knobs the embedded renderer answers - fps, scaling, audio.
//   A control for a flag WallpaperEngineSurface does not read would be a
//   fake action, so nothing else is offered.
//
// The online sources get no sidebar: their controls (resolution, provider)
// already live in the top toolbar and there is nothing filesystem-shaped to
// navigate.
ColumnLayout {
    id: root

    // "local" | "wallpaperEngine" | an online provider - the content host's
    // own source string.
    property string source: "local"

    spacing: Appearance.spacing.space100

    readonly property var weConfig: Config.options.wallpaperSelector.wallpaperEngine
    readonly property string activeProjectId: root.weConfig.activeProject
    readonly property bool hasProjectOverride: WallpaperEngineOverrides.ready
        && WallpaperEngineOverrides.hasOverride(root.activeProjectId)
    // What the three controls show and edit: the active project's own record
    // while the override switch is on, the globals otherwise.
    readonly property bool editingOverride: root.hasProjectOverride
    readonly property var effective: WallpaperEngineOverrides.active

    function writeSetting(key, value) {
        if (root.editingOverride) {
            WallpaperEngineOverrides.setOverride(root.activeProjectId, key, value);
            return;
        }
        if (key === "fps")
            root.weConfig.fps = value;
        else if (key === "scaling")
            root.weConfig.scaling = value;
        else if (key === "silent")
            root.weConfig.silent = value;
    }

    StyledText {
        Layout.leftMargin: Appearance.spacing.space150
        Layout.topMargin: Appearance.spacing.space100
        text: root.source === "wallpaperEngine"
            ? Translation.tr("Wallpaper Engine")
            : Translation.tr("Places")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    // ---- Places rail (local files) -------------------------------------
    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        active: root.source === "local"
        visible: active

        sourceComponent: ColumnLayout {
            spacing: Appearance.spacing.space25

            Repeater {
                model: SelectorPlaces.places({
                    home: FileUtils.trimFileProtocol(Directories.home),
                    documents: FileUtils.trimFileProtocol(Directories.documents),
                    downloads: FileUtils.trimFileProtocol(Directories.downloads),
                    pictures: FileUtils.trimFileProtocol(Directories.pictures),
                    videos: FileUtils.trimFileProtocol(Directories.videos)
                }, {
                    showHomePath: Config.options.wallpaperSelector.showHomePath,
                    weeb: Config.options.policies.weeb,
                    userPath: Config.options.wallpaperSelector.userPath ?? ""
                })

                delegate: RippleButton {
                    id: placeButton
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 38
                    buttonRadius: height / 2
                    toggled: SelectorPlaces.isCurrent(placeButton.modelData.path,
                        Wallpapers.directory)
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                    onClicked: Wallpapers.setDirectory(placeButton.modelData.path)
                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.spacing.space150
                        anchors.rightMargin: Appearance.spacing.space150
                        spacing: Appearance.spacing.space100
                        MaterialSymbol {
                            text: placeButton.modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            fill: placeButton.toggled ? 1 : 0
                            color: placeButton.toggled
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: placeButton.modelData.translate
                                ? Translation.tr(placeButton.modelData.name)
                                : placeButton.modelData.name
                            color: placeButton.toggled
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ---- Engine configuration (Wallpaper Engine) -----------------------
    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        active: root.source === "wallpaperEngine"
        visible: active

        sourceComponent: ColumnLayout {
            spacing: Appearance.spacing.space100

            // The active project's card. Absent, the section simply is not
            // drawn - an empty preview frame is a promise about a selection
            // that does not exist.
            Rectangle {
                Layout.fillWidth: true
                visible: root.activeProjectId !== ""
                implicitHeight: activeCard.implicitHeight + Appearance.spacing.space150 * 2
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: activeCard
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: Appearance.spacing.space150
                    }
                    spacing: Appearance.spacing.space100

                    StyledImage {
                        Layout.fillWidth: true
                        Layout.preferredHeight: width * 9 / 16
                        fillMode: Image.PreserveAspectCrop
                        source: root.weConfig.activePreview
                        // A thumbnail-sized decode of a preview drawn ~200px
                        // wide; the card is width-stable so the constant
                        // avoids the bound-to-geometry reload trap.
                        sourceSize.width: 400
                        sourceSize.height: 225
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: activeCard.width
                                height: activeCard.width * 9 / 16
                                radius: Appearance.rounding.small
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: WallpaperEngine.projects.find(
                            p => p.id === root.activeProjectId)?.title ?? root.activeProjectId
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        buttonRadius: height / 2
                        onClicked: WallpaperEngine.stop()
                        contentItem: RowLayout {
                            anchors.fill: parent
                            spacing: Appearance.spacing.space75
                            Item { Layout.fillWidth: true }
                            MaterialSymbol {
                                text: "stop_circle"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: Translation.tr("Clear selection")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }

            ConfigSwitch {
                Layout.fillWidth: true
                visible: root.activeProjectId !== ""
                buttonIcon: "tune"
                text: Translation.tr("Custom settings")
                description: Translation.tr("Only this wallpaper")
                checked: root.hasProjectOverride
                onToggleRequested: {
                    if (root.hasProjectOverride) {
                        WallpaperEngineOverrides.clearOverrides(root.activeProjectId);
                    } else {
                        // Seed the record from what runs right now, so
                        // flipping the switch changes nothing on screen until
                        // a control is moved.
                        WallpaperEngineOverrides.setOverride(root.activeProjectId, "fps", root.effective.fps);
                        WallpaperEngineOverrides.setOverride(root.activeProjectId, "scaling", root.effective.scaling);
                        WallpaperEngineOverrides.setOverride(root.activeProjectId, "silent", root.effective.silent);
                    }
                }
            }

            StyledText {
                Layout.leftMargin: Appearance.spacing.space150
                text: root.editingOverride
                    ? Translation.tr("This wallpaper")
                    : Translation.tr("All wallpapers")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100
                StyledText {
                    Layout.leftMargin: Appearance.spacing.space150
                    Layout.fillWidth: true
                    text: Translation.tr("Frame rate")
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                StyledComboBox {
                    id: fpsBox
                    implicitWidth: 92
                    readonly property var values: [24, 30, 60]
                    model: [
                        { value: 24, displayName: "24 FPS" },
                        { value: 30, displayName: "30 FPS" },
                        { value: 60, displayName: "60 FPS" }
                    ]
                    textRole: "displayName"
                    // Bound, not set at completion: the shown value swaps
                    // between the globals and a project's record when the
                    // override switch flips.
                    currentIndex: Math.max(0, fpsBox.values.indexOf(root.effective.fps))
                    onActivated: index => root.writeSetting("fps", fpsBox.values[index])
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100
                StyledText {
                    Layout.leftMargin: Appearance.spacing.space150
                    Layout.fillWidth: true
                    text: Translation.tr("Scaling")
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                StyledComboBox {
                    id: scalingBox
                    implicitWidth: 92
                    readonly property var values: ["fill", "fit", "stretch"]
                    model: [
                        { value: "fill", displayName: Translation.tr("Fill") },
                        { value: "fit", displayName: Translation.tr("Fit") },
                        { value: "stretch", displayName: Translation.tr("Stretch") }
                    ]
                    textRole: "displayName"
                    currentIndex: Math.max(0, scalingBox.values.indexOf(root.effective.scaling))
                    onActivated: index => root.writeSetting("scaling", scalingBox.values[index])
                }
            }

            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("Wallpaper audio")
                checked: !root.effective.silent
                onToggleRequested: root.writeSetting("silent", !root.effective.silent)
            }

            // Which screen plays the sound. Only where the question exists:
            // one screen, or muted, and there is nothing to choose. Global
            // always - there is one audio route however many projects there
            // are, which is also why it is not on the override record.
            RowLayout {
                Layout.fillWidth: true
                visible: !root.effective.silent && (Quickshell.screens?.length ?? 0) > 1
                spacing: Appearance.spacing.space100
                StyledText {
                    Layout.leftMargin: Appearance.spacing.space150
                    Layout.fillWidth: true
                    text: Translation.tr("Audio on")
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                StyledComboBox {
                    id: audioOutputBox
                    implicitWidth: 116

                    readonly property var outputs: [{
                        value: "",
                        displayName: Translation.tr("Auto")
                    }].concat((Quickshell.screens ?? []).map(screen => ({
                        value: screen.name,
                        displayName: screen.name
                    })))

                    model: audioOutputBox.outputs
                    textRole: "displayName"
                    currentIndex: Math.max(0, audioOutputBox.outputs
                        .findIndex(output => output.value
                            === (root.weConfig.audioMonitor ?? "")))
                    onActivated: index =>
                        root.weConfig.audioMonitor = audioOutputBox.outputs[index].value

                    StyledToolTip {
                        text: Translation.tr("Screen that plays the wallpaper's sound")
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
