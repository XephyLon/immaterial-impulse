import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell.Hyprland


ContentPage {
    id: page
    forceWidth: true

    function goTo(term) {
        const t = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) {
                    return child
                }
            }

            for (let i = 0; i < rootItem.children.length; i++) {
                let found = findTarget(rootItem.children[i])
                if (found) return found
            }
            return null
        }

        let target = findTarget(mainLayout)
        if (target) {
            let pos = target.mapToItem(mainLayout, 0, 0)
            page.contentY = Math.max(0, pos.y - 0)
        }
    }

    function displayPathFor(path) {
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path)
            ? Config.options.background.thumbnailPath
            : path
    }

    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: Appearance.spacing.space250
            
        ContentSection {
            icon: "panorama"
            title: Translation.tr("Wallpaper")
            shape: MaterialShape.Shape.Clover4Leaf

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: wrapperCol.implicitHeight + Appearance.spacing.space200
                topLeftRadius: Appearance.rounding.verylarge
                topRightRadius: Appearance.rounding.verylarge
                bottomLeftRadius: Appearance.rounding.normal
                bottomRightRadius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: wrapperCol
                    anchors.fill: parent
                    anchors.margins: Appearance.spacing.space100
                    spacing: Appearance.spacing.space100

                    Carousel {
                        Layout.fillWidth: true
                        implicitHeight: 280
                        largeItemWidthRatio: 0.5
                        mediumItemWidthRatio: 0.485
                        itemSpacing: Appearance.spacing.space100
                        wheelEnabled: false
                        dragEnabled: false
                        clickAction: (index, modelData) => {
                            GlobalStates.wallpaperSelectorTarget = index === 1 ? "lockWall" : "wallpaper"
                            GlobalStates.wallpaperSelectorOpen = true
                        }
                        // WE-aware artwork (engine preview when a WE project is
                        // active), routed through displayPathFor so a video
                        // wallpaper shows its generated thumbnail instead of a
                        // non-renderable video path (upstream vb).
                        model: [
                            page.displayPathFor(WallpaperEngine.activeArtwork),
                            page.displayPathFor(
                                Config.options.background.lockWall !== ""
                                    ? Config.options.background.lockWall
                                    : WallpaperEngine.activeArtwork
                            )
                        ]
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space100

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: Appearance.rounding.normal
                            color: "transparent"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: Appearance.spacing.space100
                                MaterialSymbol {
                                    text: "desktop_windows"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: Translation.tr("Desktop")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: Appearance.rounding.normal
                            color: "transparent"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: Appearance.spacing.space100
                                MaterialSymbol {
                                    text: "lock"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: Translation.tr("Lockscreen")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }


            GroupedList {
                Layout.topMargin: -Appearance.spacing.space25

                ConfigSwitch {
                    id: syncWallpaperSwitch
                    buttonIcon: "sync"
                    text: Translation.tr("Use same wallpaper for both")
                    checked: Config.options.background.lockWall === ""
                        && Config.options.background.lockWallEngine === ""
                    // One-way: clearing both paths is what "same wallpaper"
                    // means, and there is no stored lockscreen wallpaper to put
                    // back, so a click while it is already on stays a no-op.
                    onToggleRequested: {
                        Config.options.background.lockWall = "";
                        Config.options.background.lockWallEngine = "";
                    }
                }

                ConfigSwitch {
                    buttonIcon: "preview"
                    text: Translation.tr("Preview wallpaper")
                    checked: Config.options.background.enableWallpaperPreview
                    onToggleRequested: Config.options.background.enableWallpaperPreview = !Config.options.background.enableWallpaperPreview
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Wallpaper change interval (min)")
                    value: Config.options.wallpaperSelector.changeInterval / 60000
                    from: 0
                    to: 1440
                    stepSize: 5
                    onValueModified: {
                        Config.options.wallpaperSelector.changeInterval = newValue * 60000;
                    }
                }

                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "texture"
                    text: Translation.tr("Transitions")
                    fieldWidth: 50
                    model: WallpaperTransitions.options
                    currentValue: Config.options.background.wallpaperAnimation
                    onSelected: newValue => {
                        Config.options.background.wallpaperAnimation = newValue;
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Parallax")
                Layout.fillWidth: true

                GroupedList {
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "animation"
                        text: Translation.tr("Enable")
                        checked: Config.options.background.parallax.enable
                        onToggleRequested: Config.options.background.parallax.enable = !Config.options.background.parallax.enable
                    }
                    ConfigSpinBox {
                        Layout.fillWidth: true
                        enabled: Config.options.background.parallax.enable
                        text: Translation.tr("Zoom (%)")
                        // The zoom IS the room the pan happens in: at 100% the
                        // wallpaper is exactly screen-sized and every switch
                        // below it does nothing, so the floor is 100 rather
                        // than something that silently disables the feature.
                        from: 100
                        to: 150
                        stepSize: 1
                        value: Math.round(Config.options.background.parallax.workspaceZoom * 100)
                        onValueModified: newValue => {
                            Config.options.background.parallax.workspaceZoom = newValue / 100;
                        }
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "view_carousel"
                        enabled: Config.options.background.parallax.enable
                        text: Translation.tr("Follow workspaces")
                        checked: Config.options.background.parallax.enableWorkspace
                        onToggleRequested: Config.options.background.parallax.enableWorkspace = !Config.options.background.parallax.enableWorkspace
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "dock_to_right"
                        enabled: Config.options.background.parallax.enable
                        text: Translation.tr("Follow sidebars")
                        checked: Config.options.background.parallax.enableSidebar
                        onToggleRequested: Config.options.background.parallax.enableSidebar = !Config.options.background.parallax.enableSidebar
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "widgets"
                        enabled: Config.options.background.parallax.enable
                        text: Translation.tr("Move desktop widgets")
                        checked: Config.options.background.parallax.enableWidgets
                        onToggleRequested: Config.options.background.parallax.enableWidgets = !Config.options.background.parallax.enableWidgets
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "swap_vert"
                        enabled: Config.options.background.parallax.enable
                        text: Translation.tr("Pan vertically")
                        checked: Config.options.background.parallax.vertical
                        onToggleRequested: Config.options.background.parallax.vertical = !Config.options.background.parallax.vertical
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "auto_awesome"
                        enabled: Config.options.background.parallax.enable && !Config.options.background.parallax.vertical
                        text: Translation.tr("Pan vertically on portrait wallpapers")
                        checked: Config.options.background.parallax.autoVertical
                        onToggleRequested: Config.options.background.parallax.autoVertical = !Config.options.background.parallax.autoVertical
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Depth")
                Layout.fillWidth: true

                GroupedList {
                    ConfigSwitch {
                        id: clockDepthSwitch
                        Layout.fillWidth: true
                        buttonIcon: "layers"
                        text: Translation.tr("Widgets behind the wallpaper's subject")
                        // The switch alone changes nothing on screen: depth is a
                        // per-wallpaper artifact accepted in the wallpaper
                        // selector, and this only decides whether an accepted one
                        // is drawn. Off by default, because a feature that puts
                        // pixels over the clock ships off.
                        checked: Config.options.background.clockDepth.enable
                        onToggleRequested: Config.options.background.clockDepth.enable = !Config.options.background.clockDepth.enable
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Centered wallpaper")
                Layout.fillWidth: true

                GroupedList {
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.background.centeredWallpaper
                        onToggleRequested: Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "lock"
                        text: Translation.tr("Show only when locked")
                        checked: Config.options.background.centeredWallpaperOnlyWhenLocked
                        onToggleRequested: Config.options.background.centeredWallpaperOnlyWhenLocked = !Config.options.background.centeredWallpaperOnlyWhenLocked
                        enabled: Config.options.background.centeredWallpaper
                    }
                }

                GroupedList {
                    Layout.topMargin: 0
                    visible: Config.options.background.centeredWallpaper
                    ConfigSelectionShapeArray {
                        currentValue: Config.options.background.centeredWallpaperShape
                        shapeColor: Appearance.colors.colPrimary
                        backgroundColor: Appearance.colors.colPrimaryContainer
                        options: [
                            "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
                            "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
                            "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
                            "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
                            "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
                        ]
                        onSelected: newValue => {
                            Config.options.background.centeredWallpaperShape = newValue
                        }
                    }
                    ColorSelectionArray {
                        visible: Config.options.background.centeredWallpaper
                        icon: "palette"
                        text: Translation.tr("Background Color")
                        currentValue: Config.options.background.centeredWallpaperColor
                        onSelected: newValue => {
                            Config.options.background.centeredWallpaperColor = newValue
                        }
                    }
                    ConfigSlider {
                        visible: Config.options.background.centeredWallpaper
                        text: Translation.tr("Size")
                        value: Config.options.background.centeredWallpaperSize
                        usePercentTooltip: false
                        buttonIcon: "aspect_ratio"
                        from: 400
                        to: 800
                        stopIndicatorValues: [400]
                        onValueModified: {
                            Config.options.background.centeredWallpaperSize = newValue;
                        }
                    }
                }
            }
        }


        ContentSection {
            shape: MaterialShape.Shape.Puffy
            icon: "panorama"
            title: Translation.tr("Wallpaper selector")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "ad"
                    text: Translation.tr('Use system file picker')
                    checked: Config.options.wallpaperSelector.useSystemFileDialog
                    onToggleRequested: Config.options.wallpaperSelector.useSystemFileDialog = !Config.options.wallpaperSelector.useSystemFileDialog
                }

                ConfigSwitch {
                    buttonIcon: "home"
                    text: Translation.tr('Show home directory in quick access')
                    checked: Config.options.wallpaperSelector.showHomePath
                    onToggleRequested: Config.options.wallpaperSelector.showHomePath = !Config.options.wallpaperSelector.showHomePath
                }

                ConfigSwitch {
                    buttonIcon: "done"
                    text: Translation.tr('Close after selection')
                    checked: Config.options.wallpaperSelector.closeAfterSelection
                    onToggleRequested: Config.options.wallpaperSelector.closeAfterSelection = !Config.options.wallpaperSelector.closeAfterSelection
                }

                ConfigSwitch {
                    buttonIcon: "blur_on"
                    text: Translation.tr('Show blur background')
                    checked: Config.options.wallpaperSelector.showBlurBackground
                    onToggleRequested: Config.options.wallpaperSelector.showBlurBackground = !Config.options.wallpaperSelector.showBlurBackground
                }

                ConfigSpinBox {
                    icon: "grid_on"
                    text: Translation.tr("Columns in grid view")
                    value: Config.options.wallpaperSelector.columns
                    from: 3
                    to: 10
                    stepSize: 1
                    onValueModified: {
                        Config.options.wallpaperSelector.columns = newValue;
                    }
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Wallpaper change interval (min)")
                    value: Config.options.wallpaperSelector.changeInterval / 60000
                    from: 0
                    to: 1440
                    stepSize: 5
                    onValueModified: {
                        Config.options.wallpaperSelector.changeInterval = newValue * 60000;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "search"
                    text: Translation.tr('Always show search bar')
                    checked: Config.options.wallpaperSelector.showSearchbar
                    onToggleRequested: Config.options.wallpaperSelector.showSearchbar = !Config.options.wallpaperSelector.showSearchbar
                }
                ConfigTextArea {
                    id: userPathField
                    Layout.fillWidth: true
                    buttonIcon: "folder"
                    text: Translation.tr("Custom Wallpaper Folder")
                    placeholderText: Translation.tr("e.g., /home/user/Pictures")
                    fieldWidth: 300
                    value: Config.options.wallpaperSelector.userPath ?? ""

                    onValueChanged: {
                        userPathDebounceTimer.restart()
                    }

                    Timer {
                        id: userPathDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.wallpaperSelector.userPath = userPathField.value
                        }
                    }
                }
                ConfigTextArea {
                    id: liveWallpapersPathField
                    Layout.fillWidth: true
                    buttonIcon: "animated_images"
                    text: Translation.tr("Live Wallpaper Folder")
                    placeholderText: Translation.tr("e.g., /home/user/Videos/Wallpapers")
                    fieldWidth: 300
                    value: Config.options.wallpaperSelector.liveWallpapersPath ?? ""

                    onValueChanged: {
                        liveWallpapersPathDebounceTimer.restart()
                    }

                    Timer {
                        id: liveWallpapersPathDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.wallpaperSelector.liveWallpapersPath = liveWallpapersPathField.value
                        }
                    }
                } 
            }
        }
    }
}
