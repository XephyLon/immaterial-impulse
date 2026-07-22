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
import Quickshell.Io

MouseArea {
    id: root
    property int columns: Config.options.wallpaperSelector.columns || 4
    property real previewCellAspectRatio: 4 / 3
    property bool useDarkMode: Appearance.m3colors.darkmode
    property bool showControls: false
    property string source: Config.options.wallpaperSelector.wallpaperEngine.activeProject !== ""
        ? "wallpaperEngine"
        : "local"
    property string selectedResolution: "1080p"
    property bool toolbarVisible: showControls || Config.options.wallpaperSelector.showSearchbar
    property bool filterFieldFocused: false
    property string wallpaperEngineSearch: ""
    property bool workshopLoadedThisOpen: false

    function loadWorkshopOnce() {
        if (source !== "wallpaperEngine" || workshopLoadedThisOpen)
            return
        workshopLoadedThisOpen = true
        WallpaperEngine.refresh()
    }

    onSourceChanged: {
        if (source === "wallpaperEngine") {
            showControls = true
            loadWorkshopOnce()
        }
    }

    Component.onCompleted: {
        if (source === "wallpaperEngine") {
            showControls = true
            loadWorkshopOnce()
        }
    }

    property var quickDirs: [
        { icon: "home",       name: "Home   ",       path: `${Directories.home}`,                alwaysVisible: Config.options.wallpaperSelector.showHomePath },
        { icon: "wallpaper",  name: "Wallpapers   ", path: `${Directories.pictures}/Wallpapers`, alwaysVisible: true },
        { icon: "imagesmode", name: "Homework   ",   path: `${Directories.pictures}/homework`,   alwaysVisible: Config.options.policies.weeb },
        { icon: "casino",     name: "Random   ",     path: `${Directories.pictures}/Random`,     alwaysVisible: true },
        { 
            icon: "image",     
            name: Config.options.wallpaperSelector.userPath?.trim().length > 0 
                ? Config.options.wallpaperSelector.userPath.split("/").filter(s => s.length > 0).pop() + "   "
                : "Custom   ",
            path: Config.options.wallpaperSelector.userPath, 
            alwaysVisible: Config.options.wallpaperSelector.userPath?.trim().length > 0 
        }
    ]

    function updateThumbnails() {
        const item = gridLoader.item;
        const totalImageMargin = (Appearance.sizes.wallpaperSelectorItemMargins + Appearance.sizes.wallpaperSelectorItemPadding) * 2;
        const cellW = item?.cellWidth ?? (wallpaperGridBackground.width / root.columns);
        const cellH = item?.cellHeight ?? (cellW / root.previewCellAspectRatio);
        const thumbnailSizeName = Images.thumbnailSizeNameForDimensions(cellW - totalImageMargin, cellH - totalImageMargin);
        Wallpapers.setDirectory(`${Directories.pictures}/Wallpapers`);
        Qt.callLater(() => Wallpapers.generateThumbnail(thumbnailSizeName));
    }

    function handleFilePasting(event) {
        const currentClipboardEntry = Cliphist.entries[0];
        if (/^\d+\tfile:\/\/\S+/.test(currentClipboardEntry)) {
            const url = StringUtils.cleanCliphistEntry(currentClipboardEntry);
            Wallpapers.setDirectory(FileUtils.trimFileProtocol(decodeURIComponent(url)));
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }

    function selectWallpaperPath(filePath) {
        if (filePath && filePath.length > 0) {
            if (GlobalStates.wallpaperSelectorTarget === "lockWall") {
                Wallpapers.select(filePath, root.useDarkMode, finalPath => {
                    Config.options.background.lockWall = finalPath;
                    GlobalStates.wallpaperSelectorTarget = "wallpaper";
                    GlobalStates.wallpaperSelectorOpen = false;
                });
            } else {
                // Route through selectEntry (not Wallpapers.select directly) so a
                // switch from a live Wallpaper Engine wallpaper to a static image
                // still cross-fades from the engine still instead of the runtime
                // just closing. selectEntry must read the active project before
                // switchwall.sh clears it, so the transition cannot be recovered
                // after the fact.
                WallpaperEngine.selectEntry({ kind: "image", path: filePath }, root.useDarkMode);
            }
        }
    }

    function selectWallpaperEngineProject(project) {
        if (GlobalStates.wallpaperSelectorTarget === "lockWall") {
            if (project.preview)
                root.selectWallpaperPath(project.preview);
            return;
        }
        WallpaperEngine.selectEntry({ kind: "wallpaperEngine", project: project }, root.useDarkMode);
    }

    acceptedButtons: Qt.BackButton | Qt.ForwardButton
    onPressed: event => {
        if (event.button === Qt.BackButton) {
            Wallpapers.navigateBack();
        } else if (event.button === Qt.ForwardButton) {
            Wallpapers.navigateForward();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            GlobalStates.wallpaperSelectorOpen = false;
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
            root.handleFilePasting(event);
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            if (Config.options.wallpaperSelector.showSearchbar) {
                Config.options.wallpaperSelector.showSearchbar = false
                showControls = false
            } else {
                showControls = !showControls
            }
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Up) {
            Wallpapers.navigateUp();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Left) {
            Wallpapers.navigateBack();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Right) {
            Wallpapers.navigateForward();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            if (!root.filterFieldFocused) gridLoader.item?.moveSelection(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            if (!root.filterFieldFocused) gridLoader.item?.moveSelection(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            if (!root.filterFieldFocused) gridLoader.item?.moveSelection(-root.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            if (!root.filterFieldFocused) gridLoader.item?.moveSelection(root.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!root.filterFieldFocused) gridLoader.item?.activateCurrent();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (!root.filterFieldFocused) {
                filterField.forceActiveFocus();
            }
            event.accepted = true;
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_L) {
            addressBar.focusBreadcrumb();
            event.accepted = true;
        } else if (event.key === Qt.Key_Slash) {
            filterField.forceActiveFocus();
            event.accepted = true;
        } else {
            if (event.text.length > 0 && !root.filterFieldFocused) {
                filterField.text += event.text;
                filterField.cursorPosition = filterField.text.length;
                filterField.forceActiveFocus();
            }
            event.accepted = true;
        }
    }

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: mainLayout.implicitWidth

    StyledRectangularShadow {
        target: wallpaperGridBackground
    }
    Rectangle {
        id: wallpaperGridBackground
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        focus: true
        border.width: Appearance.borderWidth.standard
        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding + 5

        implicitWidth: gridColumnLayout.implicitWidth
        implicitHeight: gridColumnLayout.implicitHeight

        Item {
            anchors { fill: parent; margins: Appearance.spacing.space100 }
            z: 0

            Rectangle {
                anchors.fill: parent
                radius: wallpaperGridBackground.radius - 4
                color: Appearance.colors.colLayer2
                visible: !Config.options.wallpaperSelector.showBlurBackground
            }

            StyledImage {
                id: wallpaperBgImage
                anchors.fill: parent
                visible: Config.options.wallpaperSelector.showBlurBackground
                fillMode: Image.PreserveAspectCrop
                source: Config.options.background.wallpaperPath
                cache: false
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: wallpaperGridBackground.width - 16
                        height: wallpaperGridBackground.height - 16
                        radius: wallpaperGridBackground.radius - 4
                    }
                }
            }

            FastBlur {
                anchors.fill: parent
                z: 0
                visible: Config.options.wallpaperSelector.showBlurBackground
                source: wallpaperBgImage
                radius: 48
                layer.enabled: visible
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: wallpaperGridBackground.width - 16
                        height: wallpaperGridBackground.height - 16
                        radius: wallpaperGridBackground.radius - 4
                    }
                }
            }
        }

        RowLayout {
            id: mainLayout
            anchors.fill: parent
            anchors.topMargin: 0
            anchors.bottomMargin: Appearance.spacing.space100
            anchors.leftMargin: Appearance.spacing.space100
            anchors.rightMargin: Appearance.spacing.space100
            spacing: -Appearance.spacing.space50
            z: 1

            ColumnLayout {
                id: gridColumnLayout
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: topBar
                    Layout.fillWidth: true
                    Layout.margins: Appearance.spacing.space200
                    Layout.leftMargin: Appearance.spacing.space250
                    implicitHeight: 56

                    RowLayout {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: Appearance.spacing.space100

                        MaterialShapeWrappedMaterialSymbol {
                            wrappedShape: MaterialShape.Shape.Gem
                            text: "image"
                            iconSize: Appearance.font.pixelSize.larger
                        }

                        StyledText {
                            text: Translation.tr("Wallpaper Selector")
                            font.pixelSize: Appearance.font.pixelSize.large
                        }
                    }

                    Toolbar {
                        anchors.centerIn: parent

                        Loader {
                            active: root.source === "local"
                            visible: active
                            sourceComponent: RowLayout {
                                spacing: Appearance.spacing.space50
                                Repeater {
                                    model: root.quickDirs
                                    delegate: RippleButton {
                                        id: dirBtn
                                        required property var modelData
                                        implicitHeight: 38
                                        buttonRadius: height / 2
                                        visible: modelData.alwaysVisible
                                        toggled: Wallpapers.directory === Qt.resolvedUrl(modelData.path)
                                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                                        colRippleToggled: Appearance.colors.colSecondaryContainerActive
                                        onClicked: Wallpapers.setDirectory(modelData.path)
                                        contentItem: RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Appearance.spacing.space150
                                            anchors.rightMargin: Appearance.spacing.space150
                                            spacing: Appearance.spacing.space100
                                            MaterialSymbol {
                                                text: dirBtn.modelData.icon
                                                iconSize: Appearance.font.pixelSize.larger
                                                color: dirBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                                fill: dirBtn.toggled ? 1 : 0
                                            }
                                            StyledText {
                                                text: dirBtn.modelData.name
                                                color: dirBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Loader {
                            active: root.source !== "local" && root.source !== "wallpaperEngine"
                            visible: active
                            sourceComponent: RowLayout {
                                spacing: Appearance.spacing.space50
                                Repeater {
                                    model: ["1080p", "2K", "4K"]
                                    delegate: RippleButton {
                                        required property string modelData
                                        implicitHeight: 38
                                        buttonRadius: height / 2
                                        toggled: root.selectedResolution === modelData
                                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                                        colRippleToggled: Appearance.colors.colSecondaryContainerActive
                                        onClicked: root.selectedResolution = modelData
                                        contentItem: StyledText {
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: parent.toggled
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colOnLayer2
                                        }
                                    }
                                }
                            }
                        }

                        Loader {
                            active: root.source === "wallpaperEngine"
                            visible: active
                            sourceComponent: RowLayout {
                                spacing: Appearance.spacing.space100

                                StyledText {
                                    text: Translation.tr("Steam Workshop")
                                    color: Appearance.colors.colOnLayer2
                                }

                                StyledComboBox {
                                    implicitWidth: 92
                                    model: [
                                        { value: 24, displayName: "24 FPS" },
                                        { value: 30, displayName: "30 FPS" },
                                        { value: 60, displayName: "60 FPS" }
                                    ]
                                    textRole: "displayName"
                                    Component.onCompleted: {
                                        const configured = Config.options.wallpaperSelector.wallpaperEngine.fps;
                                        currentIndex = configured === 24 ? 0 : configured === 60 ? 2 : 1;
                                    }
                                    onActivated: index => Config.options.wallpaperSelector.wallpaperEngine.fps = model[index].value
                                }

                                StyledComboBox {
                                    implicitWidth: 90
                                    model: [
                                        { value: "fill", displayName: Translation.tr("Fill") },
                                        { value: "fit", displayName: Translation.tr("Fit") },
                                        { value: "stretch", displayName: Translation.tr("Stretch") }
                                    ]
                                    textRole: "displayName"
                                    Component.onCompleted: {
                                        const configured = Config.options.wallpaperSelector.wallpaperEngine.scaling;
                                        currentIndex = configured === "fit" ? 1 : configured === "stretch" ? 2 : 0;
                                    }
                                    onActivated: index => Config.options.wallpaperSelector.wallpaperEngine.scaling = model[index].value
                                }

                                RippleButton {
                                    implicitWidth: 38
                                    implicitHeight: 38
                                    buttonRadius: height / 2
                                    toggled: Config.options.wallpaperSelector.wallpaperEngine.silent
                                    onClicked: Config.options.wallpaperSelector.wallpaperEngine.silent = !Config.options.wallpaperSelector.wallpaperEngine.silent
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: Config.options.wallpaperSelector.wallpaperEngine.silent ? "volume_off" : "volume_up"
                                        color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                    }
                                    StyledToolTip { text: Translation.tr("Wallpaper audio") }
                                }
                            }
                        }
                    }

                    RowLayout {
                        anchors {
                            right: parent.right
                            rightMargin: Appearance.spacing.space100
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: Appearance.spacing.space100

                        StyledComboBox {
                            id: sourceCombo
                            implicitWidth: 168
                            model: [
                                { value: "local",     displayName: Translation.tr("Local") },
                                { value: "wallpaperEngine", displayName: Translation.tr("Wallpaper Engine") },
                                { value: "wallhaven", displayName: Translation.tr("Wallhaven") },
                                { value: "unsplash",  displayName: Translation.tr("Unsplash") },
                                { value: "pexels",    displayName: Translation.tr("Pexels") },
                            ]
                            textRole: "displayName"
                            currentIndex: root.source === "wallpaperEngine" ? 1
                                : root.source === "wallhaven" ? 2
                                : root.source === "unsplash" ? 3
                                : root.source === "pexels" ? 4
                                : 0
                            onActivated: index => {
                                root.source = model[index].value
                                root.forceActiveFocus()
                            }
                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: height / 2
                            toggled: root.toolbarVisible
                            colBackground: Appearance.colors.colSecondaryContainer
                            onClicked: {
                                if (Config.options.wallpaperSelector.showSearchbar) {
                                    Config.options.wallpaperSelector.showSearchbar = false
                                    showControls = false
                                } else {
                                    showControls = !showControls
                                }
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "search"
                                iconSize: Appearance.font.pixelSize.larger
                                color: root.toolbarVisible
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnSecondaryContainer
                            }
                            StyledToolTip {
                                text: Translation.tr("Toggle search toolbar (Ctrl+F)")
                            }
                        }
                    }
                }

                Item {
                    id: gridDisplayRegion
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Loader {
                        id: gridLoader
                        anchors.fill: parent
                        sourceComponent: root.source === "local"
                            ? localGridComponent
                            : root.source === "wallpaperEngine"
                                ? wallpaperEngineGridComponent
                                : onlineGridComponent
                    }

                    Component {
                        id: localGridComponent
                        LocalWallpaperGrid {
                            columns: root.columns
                            previewCellAspectRatio: root.previewCellAspectRatio
                            onWallpaperSelected: path => root.selectWallpaperPath(path)
                        }
                    }

                    Component {
                        id: wallpaperEngineGridComponent
                        WallpaperEngineGrid {
                            columns: root.columns
                            previewCellAspectRatio: root.previewCellAspectRatio
                            searchQuery: root.wallpaperEngineSearch
                            onProjectSelected: project => root.selectWallpaperEngineProject(project)
                        }
                    }

                    Component {
                        id: onlineGridComponent
                        OnlineWallpaperGrid {
                            provider: root.source
                            resolution: root.selectedResolution
                            onWallpaperSelected: path => root.selectWallpaperPath(path)
                            onUpdateThumbnailsRequested: root.updateThumbnails()
                        }
                    }

                    Row {
                        id: extraOptions
                        anchors {
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                            bottomMargin: Appearance.spacing.space100
                        }
                        spacing: Appearance.spacing.space100
                        z: root.toolbarVisible ? 2 : -1
                        opacity: root.toolbarVisible ? 1 : 0
                        transform: Translate {
                            y: root.toolbarVisible ? 0 : 20
                            Behavior on y {
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }

                        Loader {
                            active: root.source === "local"
                            visible: active
                            sourceComponent: Toolbar {
                                IconToolbarButton {
                                    implicitWidth: height
                                    onClicked: {
                                        Wallpapers.openFallbackPicker(root.useDarkMode);
                                        GlobalStates.wallpaperSelectorOpen = false;
                                    }
                                    altAction: () => {
                                        Wallpapers.openFallbackPicker(root.useDarkMode);
                                        GlobalStates.wallpaperSelectorOpen = false;
                                        Config.options.wallpaperSelector.useSystemFileDialog = true;
                                    }
                                    text: "open_in_new"
                                }
                                IconToolbarButton {
                                    implicitWidth: height
                                    onClicked: Wallpapers.randomFromCurrentFolder()
                                    text: "ifl"
                                }
                                IconToolbarButton {
                                    implicitWidth: height
                                    onClicked: root.useDarkMode = !root.useDarkMode
                                    text: root.useDarkMode ? "dark_mode" : "light_mode"
                                }
                                IconToolbarButton {
                                    implicitWidth: height
                                    onClicked: root.updateThumbnails()
                                    text: "reset_image"
                                }
                                ToolbarTextField {
                                    id: filterField
                                    placeholderText: focus
                                        ? Translation.tr("Search wallpapers")
                                        : Translation.tr("Search wallpapers")
                                    clip: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onTextChanged: Wallpapers.searchQuery = text
                                    onActiveFocusChanged: root.filterFieldFocused = activeFocus
                                    Keys.onPressed: event => {
                                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                            root.handleFilePasting(event);
                                            event.accepted = true;
                                            return;
                                        }
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            event.accepted = true;
                                            return;
                                        }
                                        if (text.length !== 0) {
                                            if (event.key === Qt.Key_Down) { event.accepted = true; return; }
                                            if (event.key === Qt.Key_Up)   { event.accepted = true; return; }
                                        }
                                        event.accepted = false;
                                    }
                                }
                            }
                        }

                        Loader {
                            active: root.source === "wallpaperEngine"
                            visible: active
                            sourceComponent: Toolbar {
                                ToolbarTextField {
                                    placeholderText: Translation.tr("Search Wallpaper Engine projects")
                                    clip: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onTextChanged: root.wallpaperEngineSearch = text
                                    onActiveFocusChanged: root.filterFieldFocused = activeFocus
                                }
                                IconToolbarButton {
                                    text: "refresh"
                                    enabled: !WallpaperEngine.loading
                                    onClicked: WallpaperEngine.refresh()
                                }
                                IconToolbarButton {
                                    text: "stop_circle"
                                    enabled: Config.options.wallpaperSelector.wallpaperEngine.activeProject !== ""
                                    onClicked: WallpaperEngine.stop()
                                    StyledToolTip { text: Translation.tr("Clear Wallpaper Engine selection") }
                                }
                            }
                        }

                        Loader {
                            active: root.source !== "local" && root.source !== "wallpaperEngine"
                            visible: active
                            sourceComponent: Toolbar {
                                ToolbarTextField {
                                    id: onlineSearchField
                                    placeholderText: Translation.tr("Search online wallpapers")
                                    clip: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onTextChanged: OnlineWallpapers.query = text
                                    onAccepted: OnlineWallpapers.fetch()
                                    onActiveFocusChanged: root.filterFieldFocused = activeFocus
                                    Connections {
                                        target: GlobalStates
                                        function onWallpaperSelectorOpenChanged() {
                                            if (!GlobalStates.wallpaperSelectorOpen) onlineSearchField.text = ""
                                        }
                                    }
                                    Keys.onPressed: event => {
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            event.accepted = true;
                                            return;
                                        }
                                        event.accepted = false;
                                    }
                                }
                                IconToolbarButton {
                                    implicitWidth: height
                                    text: "refresh"
                                    onClicked: OnlineWallpapers.fetch()
                                }
                            }
                        }

                        ToolbarPairedFab {
                            iconText: "close"
                            onClicked: GlobalStates.wallpaperSelectorOpen = false
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen && monitorIsFocused) {
                if (root.source === "wallpaperEngine") {
                    root.forceActiveFocus();
                } else if (root.source === "local")
                    filterField.forceActiveFocus()
                else
                    root.forceActiveFocus()
            }
        }
    }

    Connections {
        target: Wallpapers
        function onChanged() {
            if (Config.options.wallpaperSelector.closeAfterSelection)
                GlobalStates.wallpaperSelectorOpen = false;
        }
    }

    Connections {
        target: WallpaperEngine
        function onApplied() {
            if (Config.options.wallpaperSelector.closeAfterSelection)
                GlobalStates.wallpaperSelectorOpen = false;
        }
    }
}
