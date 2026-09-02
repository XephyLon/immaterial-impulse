pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.dropShelf
import qs.modules.common.functions

Scope {
    id: root

    function openCentered(shouldOpen) {
        if (!shouldOpen) {
            GlobalStates.desktopMenuOpen = false
            return
        }
        const focusedName = Hyprland.focusedMonitor?.name
        const screen = Quickshell.screens.find(s => s.name === focusedName) ?? Quickshell.screens[0]
        GlobalStates.desktopMenuScreen = screen
        GlobalStates.desktopMenuX = screen.width / 2
        GlobalStates.desktopMenuY = screen.height / 2
        GlobalStates.desktopMenuOpen = true
    }

    function displayPathFor(path) {
        if (!path) return path
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path)
            ? Config.options.background.thumbnailPath
            : path
    }

    // Wallpaper folder images
    FolderListModel {
        id: wallpaperFolder
        folder: {
            const wallPath = Config.options.background.wallpaperPath
            if (!wallPath || wallPath.length === 0) return ""
            const lastSlash = wallPath.lastIndexOf("/")
            return "file://" + wallPath.substring(0, lastSlash)
        }
        showDirs: false
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
    }

    property int carouselExtraCount: 5
    property bool useDarkMode: Appearance.m3colors.darkmode
    property var staticWallpaperEntries: {
        const current = FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)
        let all = []
        for (let i = 0; i < wallpaperFolder.count; i++) {
            const fp = FileUtils.trimFileProtocol(wallpaperFolder.get(i, "filePath").toString())
            if (fp !== current) all.push({ kind: "static", artwork: root.displayPathFor(fp), path: fp })
        }
        return all
    }

    property var wallpaperEngineEntries: WallpaperEngine.projects.map(project => ({
        kind: "wallpaperEngine",
        artwork: project.id === Config.options.wallpaperSelector.wallpaperEngine.activeProject
            ? WallpaperEngine.activeArtwork
            : project.preview,
        project: project
    })).filter(entry => entry.artwork && entry.artwork.length > 0)

    property var carouselModel: {
        const engine = Config.options.wallpaperSelector.wallpaperEngine
        const currentStatic = FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)
        let currentEntry = null
        let staticExtras = staticWallpaperEntries.slice()
        let engineExtras = wallpaperEngineEntries.slice()

        if (engine.activeProject) {
            currentEntry = wallpaperEngineEntries.find(entry => entry.project.id === engine.activeProject)
            if (!currentEntry && WallpaperEngine.activeArtwork) {
                currentEntry = {
                    kind: "wallpaperEngine",
                    artwork: WallpaperEngine.activeArtwork,
                    project: {
                        id: engine.activeProject,
                        path: engine.activePath,
                        preview: engine.activePreview
                    }
                }
            }
            engineExtras = engineExtras.filter(entry => entry.project.id !== engine.activeProject)
        } else if (currentStatic) {
            currentEntry = { kind: "static", artwork: root.displayPathFor(currentStatic), path: currentStatic }
            staticExtras = staticExtras.filter(entry => entry.path !== currentStatic)
        }

        for (let i = staticExtras.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [staticExtras[i], staticExtras[j]] = [staticExtras[j], staticExtras[i]]
        }
        for (let i = engineExtras.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [engineExtras[i], engineExtras[j]] = [engineExtras[j], engineExtras[i]]
        }

        // Interleave both sources so installed Wallpaper Engine projects cannot
        // disappear behind a large static-wallpaper directory.
        let visibleExtras = []
        while (visibleExtras.length < carouselExtraCount
                && (engineExtras.length > 0 || staticExtras.length > 0)) {
            if (engineExtras.length > 0) visibleExtras.push(engineExtras.shift())
            if (visibleExtras.length < carouselExtraCount && staticExtras.length > 0)
                visibleExtras.push(staticExtras.shift())
        }
        return currentEntry ? [currentEntry, ...visibleExtras] : visibleExtras
    }

    // Menu window
    Loader {
        active: GlobalStates.desktopMenuOpen
        sourceComponent: PanelWindow {
            id: menuWindow

            screen: GlobalStates.desktopMenuScreen ?? Quickshell.screens[0]

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:desktopMenu"
            WlrLayershell.layer: WlrLayer.Overlay

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            property Component openSubmenuComponent: null
            property real submenuAnchorY: 0
            property real submenuWidth: 284

            Timer {
                id: submenuCloseTimer
                interval: 250
                onTriggered: menuWindow.openSubmenuComponent = null
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: GlobalStates.desktopMenuOpen = false
            }

            // Menu card 
            Rectangle {
                id: menuCard
                width: 348
                implicitHeight: menuCol.implicitHeight + 16
                x: Math.min(Math.max(GlobalStates.desktopMenuX - width / 2, 8), menuWindow.width - width - 8)
                y: Math.min(Math.max(GlobalStates.desktopMenuY - implicitHeight / 2, 8), menuWindow.height - implicitHeight - 8)
                radius: Appearance.rounding.verylarge
                color: "transparent"

                scale: 0.85
                opacity: 0
                transformOrigin: Item.Center

                // Container, then fill: the card's own entrance is the scale
                // and opacity above, and its ROWS arrive as a group once the
                // card has mostly landed. This is the drawer's adoption shape,
                // not the sidebar's refused one: the card's opacity IS a
                // QML-readable progress for its entrance (the Behavior
                // animates the property itself), so the wave gates on the
                // real container rather than on a guessed leadIn - the exact
                // scalar whose absence is half of why the right sidebar's
                // wave came back off. Enter-only, because the close destroys
                // this window on the frame the flag drops: there is no exit
                // for a wave to animate, so nothing here calls leave().
                readonly property bool contentsIn:
                    Appearance.animation.contentsArrived(menuCard.opacity, true)
                onContentsInChanged: {
                    if (menuCard.contentsIn)
                        rowsEntrance.enter()
                }

                Component.onCompleted: {
                    // Park before the entrance starts, or the rows are drawn
                    // at full strength for the run up to the gate and then
                    // blink out to cascade back in - the arming-vs-running
                    // lesson the drawer already paid for.
                    rowsEntrance.park()
                    scale = 1.0
                    opacity = 1.0
                }

                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // The rows are RippleButtons, so each already declares
                // `appear` and folds it into its own opacity and 6px rise -
                // the wave reaches them through the property the runner
                // writes, and no dressing is declared here (a StaggerEntrance
                // aimed at controls would be the doubling the composition
                // lints fail on). `items`, not a container walk: GroupedList
                // reparents each row into its own plate, so the declared list
                // is the rows' only shared origin.
                StaggerWave {
                    id: rowsEntrance
                    target: menuGroup
                    items: menuGroup.items
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    id: menuCol
                    anchors { fill: parent; margins: Appearance.spacing.space100 }
                    spacing: Appearance.spacing.space50

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 160
                        radius: Appearance.rounding.verylarge
                        color: Appearance.colors.colLayer0
                        clip: true

                        Carousel {
                            anchors.fill: parent
                            anchors.margins: Appearance.spacing.space150
                            model: root.carouselModel
                            delegate: Component {
                                StyledImage {
                                    readonly property var entry: parent?.modelData ?? null
                                    property real fixedWidth: parent?.fixedWidth ?? width
                                    property real fixedHeight: parent?.fixedHeight ?? height
                                    source: entry?.artwork
                                        ? "file://" + FileUtils.trimFileProtocol(entry.artwork)
                                        : ""
                                    fillMode: Image.PreserveAspectCrop
                                    cache: true
                                    asynchronous: true
                                    sourceSize.width: fixedWidth * 1.5
                                    sourceSize.height: fixedHeight * 1.5
                                }
                            }
                            clickAction: (index, entry) => {
                                WallpaperEngine.selectEntry(entry, Appearance.m3colors.darkmode)
                                GlobalStates.desktopMenuOpen = false
                            }
                        }
                    }

                    GroupedList {
                        id: menuGroup
                        Layout.fillWidth: true
                        itemVerticalPadding: Appearance.spacing.space200
                        bgcolor: Appearance.colors.colLayer0

                        // Wallpapers
                        RippleButton {
                            id: wallpaperRow
                            implicitHeight: 40
                            colBackground: "transparent"
                            colRipple: Appearance.colors.colLayer2Active
                            colBackgroundHover: Appearance.colors.colLayer2
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: Appearance.spacing.space150; rightMargin: Appearance.spacing.space150 }
                                spacing: Appearance.spacing.space150
                                MaterialSymbol { text: "format_paint"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                                StyledText { Layout.fillWidth: true; text: "Wallpaper & style"; font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                MaterialSymbol { text: "chevron_right"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1; opacity: 0.4 }
                            }
                            Component {
                                id: wallpaperSubmenu
                                WallpaperSubmenu {}
                            }
                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered) {
                                        submenuCloseTimer.stop()
                                        menuWindow.submenuAnchorY = menuCard.y + wallpaperRow.mapToItem(menuCard, 0, 0).y
                                        menuWindow.openSubmenuComponent = wallpaperSubmenu
                                    } else {
                                        submenuCloseTimer.restart()
                                    }
                                }
                            }
                            // Hover opens the quick submenu; a CLICK goes to the
                            // full Settings page. It used to just close the menu -
                            // a dead click on a row drawn like a button.
                            // settingsPage carries the page's stable `id` from
                            // SettingsContent's catalogue - not its display name,
                            // which is translated, and not an index, which goes
                            // stale the day a page is inserted (the plugin
                            // context menu shipped that bug with a hardcoded
                            // index).
                            onClicked: {
                                GlobalStates.desktopMenuOpen = false
                                GlobalStates.settingsOpen = true
                                GlobalStates.settingsPage = "wallpaper-desktop"
                            }
                        }

                        // Widgets
                        RippleButton {
                            id: widgetsRow
                            implicitHeight: 40
                            colBackground: "transparent"
                            colRipple: Appearance.colors.colLayer2Active
                            colBackgroundHover: Appearance.colors.colLayer2
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: Appearance.spacing.space150; rightMargin: Appearance.spacing.space150 }
                                spacing: Appearance.spacing.space150
                                MaterialSymbol { text: "widgets"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                                StyledText { Layout.fillWidth: true; text: "Widgets"; font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                            }

                            // No hover submenu any more: WidgetsSubmenu's only
                            // live control was the global widget lock, which
                            // Edit Mode suppresses - a switch that turns off
                            // something the editor turns back on - and its
                            // widget list has been empty since the desktop
                            // widgets became plugins. The click is the row's
                            // whole meaning now, same as Edit layout below.
                            onClicked: {
                                GlobalStates.desktopMenuOpen = false
                                GlobalStates.settingsOpen = true
                                GlobalStates.settingsPage = "widgets"
                            }
                        }

                        // Edit layout. A verb, so no submenu and no chevron:
                        // unlike Wallpaper & style and Widgets, this row has no
                        // quick-settings half and no Settings page behind it.
                        //
                        // The way IN, and now only that. It stood in as the way
                        // out as well while the mode had no toolbar, because
                        // Escape depends on the compositor delivering keys to a
                        // Bottom-layer surface and that was never established -
                        // a mode whose only exit is unproven is not one to ship.
                        // The toolbar's Done is that exit now, on screen for the
                        // whole mode, so a second one here would leave the exit
                        // ALSO hidden behind a right-click, two rows deep in a
                        // context menu: precisely the discoverability failure
                        // the mode exists to fix. The row disappears while the
                        // mode is on rather than becoming a no-op, because a
                        // control that does nothing is worse than one that is
                        // not there.
                        RippleButton {
                            // `rowVisible`, not `visible`: a GroupedList row
                            // hidden the second way keeps its plate, which is
                            // the row-height band of empty `colLayer0` this
                            // menu grew between Widgets and DropShelf while the
                            // mode was on. See GroupedList.qml.
                            property bool rowVisible: !GlobalStates.editMode
                            implicitHeight: 40
                            colBackground: "transparent"
                            colRipple: Appearance.colors.colLayer2Active
                            colBackgroundHover: Appearance.colors.colLayer2
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: Appearance.spacing.space150; rightMargin: Appearance.spacing.space150 }
                                spacing: Appearance.spacing.space150
                                MaterialSymbol {
                                    text: GlobalStates.editMode ? "edit_off" : "edit"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    // One row, two states (maintainer, 2026-09-03): "Edit layout"
                                    // enters the mode; while it is on the same row reads
                                    // "Exit editing" and leaves it, beside the toolbar's Done.
                                    text: GlobalStates.editMode ? Translation.tr("Exit editing") : Translation.tr("Edit layout")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                            onClicked: {
                                GlobalStates.desktopMenuOpen = false
                                GlobalStates.editMode = !GlobalStates.editMode
                            }
                        }

                        RippleButton {
                            implicitHeight: 40
                            colBackground: "transparent"
                            colRipple: Appearance.colors.colLayer2Active
                            colBackgroundHover: Appearance.colors.colLayer2
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: Appearance.spacing.space150; rightMargin: Appearance.spacing.space150 }
                                spacing: Appearance.spacing.space150
                                MaterialSymbol { text: "stacks"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                                StyledText { Layout.fillWidth: true; text: "DropShelf"; font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                StyledText {
                                    visible: DropShelf.items.length > 0
                                    text: DropShelf.items.length
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    opacity: 0.6
                                }
                                MaterialSymbol {
                                    visible: DropShelf.items.length === 0
                                    text: "chevron_right"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer1
                                    opacity: 0.4
                                }
                            }
                            onClicked: {
                                GlobalStates.desktopMenuOpen = false
                                GlobalStates.dropShelfX = GlobalStates.desktopMenuX
                                GlobalStates.dropShelfY = GlobalStates.desktopMenuY
                                GlobalStates.dropShelfAnchorBelow = false
                                GlobalStates.dropShelfOpen = true
                            }
                        }

                        // "Live Wallpaper" used to sit here, opening the fallback
                        // picker at liveWallpapersPath. Removed: live wallpapers
                        // are picked in the wallpaper selector like everything
                        // else, and the row duplicated a path already covered by
                        // Wallpaper & style.

                        RippleButton {
                            implicitHeight: 40
                            colBackground: "transparent"
                            colRipple: Appearance.colors.colLayer2Active
                            colBackgroundHover: Appearance.colors.colLayer2
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: Appearance.spacing.space150; rightMargin: Appearance.spacing.space150 }
                                spacing: Appearance.spacing.space150
                                MaterialSymbol { text: "settings"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                                StyledText { Layout.fillWidth: true; text: "Settings"; font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                MaterialSymbol { text: "chevron_right"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1; opacity: 0.4 }
                            }
                            onClicked: {
                                GlobalStates.desktopMenuOpen = false
                                GlobalStates.settingsOpen = true
                            }
                        }
                    }
                }
            }

            // SubMenu
            Loader {
                id: submenuLoader
                active: menuWindow.openSubmenuComponent !== null
                width: menuWindow.submenuWidth
                sourceComponent: menuWindow.openSubmenuComponent

                x: (menuCard.x + menuCard.width + 8 + menuWindow.submenuWidth > menuWindow.width)
                    ? menuCard.x - menuWindow.submenuWidth - 8
                    : menuCard.x + menuCard.width + 8

                y: Math.min(
                    Math.max(menuWindow.submenuAnchorY, 8),
                    menuWindow.height - (item?.implicitHeight ?? 0) - 8
                )

                scale: active ? 1.0 : 0.9
                opacity: active ? 1.0 : 0.0
                transformOrigin: Item.Center

                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) submenuCloseTimer.stop()
                        else submenuCloseTimer.restart()
                    }
                }
            }
        }
    }
}
