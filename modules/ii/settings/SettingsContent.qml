import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.settings.pages
import qs.modules.common.widgets
import qs.modules.common.plugins
import qs.modules.common.functions as CF

Item {
    id: root
    property real contentPadding: Appearance.spacing.space100
    property int currentPage: 0
    property bool showingProfile: false
    property string navigationQuery: ""
    property string selectedSection: ""

    function normalized(value) {
        return String(value || "").toLowerCase().trim()
    }

    function pageMatches(pageIndex, page) {
        const query = normalized(navigationQuery)
        if (query.length === 0) return true
        if (normalized(page.name).includes(query)) return true
        return page.sections.some(section => sectionAvailable(pageIndex, section) && normalized(section).includes(query))
    }

    function sectionAvailable(pageIndex, section) {
        const loader = pagesRepeater.itemAt(pageIndex)
        if (!loader?.item) return true
        const available = loader.item.availableSections || []
        // A Loader can have an item before its page layout has populated the
        // section inventory. Treat that transient empty list as "not ready"
        // rather than hiding the entire branch.
        if (available.length === 0) return true
        const candidate = normalized(section)
        return available.some(actual => {
            const label = normalized(actual)
            return label === candidate || label.includes(candidate) || candidate.includes(label)
        })
    }

    function sectionMatches(pageIndex, section) {
        const query = normalized(navigationQuery)
        return sectionAvailable(pageIndex, section)
            && (query.length === 0 || normalized(section).includes(query))
    }

    function sectionIsActive(pageIndex, section) {
        if (currentPage !== pageIndex || showingProfile) return false
        const active = normalized(selectedSection)
        const candidate = normalized(section)
        if (active.length === 0 || candidate.length === 0) return false
        return active === candidate || active.includes(candidate) || candidate.includes(active)
    }

    function navigateFirstMatch() {
        const query = normalized(navigationQuery)
        if (query.length === 0) return
        for (let pageIndex = 0; pageIndex < pages.length; pageIndex++) {
            const page = pages[pageIndex]
            const matchingSection = page.sections.find(section =>
                sectionAvailable(pageIndex, section) && normalized(section).includes(query))
            if (matchingSection) {
                navigateTo(pageIndex, matchingSection)
                return
            }
            if (normalized(page.name).includes(query)) {
                navigateTo(pageIndex, "")
                return
            }
        }
    }

    function navigateTo(pageIndex, section) {
        currentPage = pageIndex
        showingProfile = false
        selectedSection = section || ""
        const loader = pagesRepeater.itemAt(pageIndex)
        const scroll = () => {
            if (section && loader?.item && typeof loader.item.goTo === "function")
                loader.item.goTo(section)
        }
        if (loader?.item) Qt.callLater(scroll)
        else if (loader) loader.onLoaded.connect(scroll)
    }

    Connections {
        target: GlobalStates
        function onSettingsPageChanged() {
            if (GlobalStates.settingsPage === "") return
            
            let parts = GlobalStates.settingsPage.split(":");
            let pageName = parts[0];
            let searchTerm = parts.length > 1 ? parts[1] : "";

            const idx = root.pages.findIndex(p => p.name.toLowerCase() === pageName.toLowerCase());
            
            if (idx >= 0) {
                root.currentPage = idx;
                root.showingProfile = false;
                
                if (searchTerm !== "") {
                    let loader = pagesRepeater.itemAt(idx);
                    if (loader && loader.item && typeof loader.item.goTo === "function") {
                        loader.item.goTo(searchTerm);
                    } else if (loader) {
                        loader.onLoaded.connect(function() {
                            if (loader.item && typeof loader.item.goTo === "function") {
                                loader.item.goTo(searchTerm);
                            }
                        });
                    }
                }
            }
            GlobalStates.settingsPage = "";
        }
    }

    onCurrentPageChanged: {
        if (currentPage === 7) {
            if (SystemInfo.cpu === "") SystemInfo.refresh()
            Updates.refresh()
        }
    }
    
    property var pages: [
        { name: Translation.tr("Quick"), icon: "instant_mix", component: Qt.resolvedUrl("pages/QuickConfig.qml"), sections: [Translation.tr("Wallpaper & Colors"), Translation.tr("Bar & Screen")] },
        { name: Translation.tr("General"), icon: "browse", component: Qt.resolvedUrl("pages/GeneralConfig.qml"), sections: [Translation.tr("Time"), Translation.tr("Left Sidebar"), Translation.tr("Right Sidebar"), Translation.tr("Battery"), Translation.tr("Audio"), Translation.tr("Sounds"), Translation.tr("Language"), Translation.tr("Work safety")] },
        { name: Translation.tr("Bar"), icon: "toast", iconRotation: 180, component: Qt.resolvedUrl("pages/BarConfig.qml"), sections: [Translation.tr("Screens"), Translation.tr("Bar layout"), Translation.tr("Positioning & Styles"), Translation.tr("Notifications"), Translation.tr("Tray"), Translation.tr("Divider"), Translation.tr("Utility buttons"), Translation.tr("Workspaces"), Translation.tr("Resources"), Translation.tr("Media"), Translation.tr("Tooltips")] },
        { name: Translation.tr("Desktop"), icon: "texture", component: Qt.resolvedUrl("pages/BackgroundConfig.qml"), sections: [Translation.tr("Wallpaper"), Translation.tr("Clock"), Translation.tr("Custom Image"), Translation.tr("Widgets")] },
        { name: Translation.tr("Plugins"), icon: "extension", component: Qt.resolvedUrl("pages/PluginsPage.qml"), sections: [Translation.tr("Available Plugins")] },
        { name: Translation.tr("Interface"), icon: "bottom_app_bar", component: Qt.resolvedUrl("pages/InterfaceConfig.qml"), sections: [Translation.tr("Overview"), Translation.tr("Dock"), Translation.tr("Lock screen"), Translation.tr("Overlay"), Translation.tr("Region selector"), Translation.tr("On-screen display"), Translation.tr("Wallpaper selector"), Translation.tr("Fonts"), Translation.tr("Terminal"), Translation.tr("Color generation")] },
        { name: Translation.tr("Services"), icon: "settings", component: Qt.resolvedUrl("pages/ServicesConfig.qml"), sections: [Translation.tr("AI"), Translation.tr("Networking"), Translation.tr("Music Recognition"), Translation.tr("Save paths"), Translation.tr("Search"), Translation.tr("System updates"), Translation.tr("Weather")] },
        { name: Translation.tr("Hyprland"), icon: "select_window_2", component: Qt.resolvedUrl("pages/HyprlandConfig.qml"), sections: [Translation.tr("Displays"), Translation.tr("Layout"), Translation.tr("Input"), Translation.tr("Visual & Aesthetics"), Translation.tr("Blur"), Translation.tr("Autostart Apps"), Translation.tr("Animations")] },
        { name: Translation.tr("About"), icon: "info", component: Qt.resolvedUrl("pages/About.qml"), sections: [] }
    ]

    Component.onCompleted: {
        Config.readWriteDelay = 0
        Qt.callLater(() => {
            for (let i = 0; i < root.pages.length; i++) {
                let loader = pagesRepeater.itemAt(i)
                if (loader) loader.active = true
            }
            if (profileLoader) profileLoader.active = true
        })
    }

    Shortcut {
        sequence: StandardKey.Find
        onActivated: settingsSearchField.forceActiveFocus()
    }

    Rectangle {
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            margins: root.contentPadding
        }
        width: navRailWrapper.implicitWidth
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerLow

        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        Rectangle {
            readonly property real contentPaneWidth: root.width - navRailWrapper.implicitWidth - (root.contentPadding * 3)
            readonly property real searchWidth: Math.min(520, contentPaneWidth)
            Layout.preferredWidth: searchWidth
            Layout.preferredHeight: 46
            Layout.leftMargin: navRailWrapper.implicitWidth + root.contentPadding
                + Math.max(0, (contentPaneWidth - searchWidth) / 2)
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Appearance.spacing.space200
                anchors.rightMargin: Appearance.spacing.space100
                spacing: Appearance.spacing.space100

                MaterialSymbol {
                    text: "search"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }

                StyledTextInput {
                    id: settingsSearchField
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.navigationQuery
                    onTextChanged: root.navigationQuery = text
                    font.pixelSize: Appearance.font.pixelSize.normal
                    Keys.onReturnPressed: root.navigateFirstMatch()
                    Keys.onEnterPressed: root.navigateFirstMatch()
                    Keys.onEscapePressed: {
                        if (text.length > 0) {
                            text = ""
                            event.accepted = true
                        }
                    }

                    HoverHandler {
                        cursorShape: Qt.IBeamCursor
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: settingsSearchField.text.length === 0
                        text: Translation.tr("Search settings and sections")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }

                RippleButton {
                    visible: root.navigationQuery.length > 0
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    onClicked: settingsSearchField.text = ""
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding

            Rectangle {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 0
                implicitWidth: navRail.expanded ? 230 : Appearance.spacing.space700
                color: "transparent"
                radius: Appearance.rounding.normal

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                NavigationRail {
                    id: navRail
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        leftMargin: Appearance.spacing.space200
                        rightMargin: Appearance.spacing.space200
                        topMargin: -Appearance.spacing.space700
                    }
                    spacing: Appearance.spacing.space150
                    expanded: root.width > 900

                    RowLayout {
                        visible: navRail.expanded
                        spacing: Appearance.spacing.space150
                        Layout.fillWidth: true
                        Layout.margins: Appearance.spacing.space100
                        Layout.topMargin: Appearance.spacing.space200

                        Rectangle {
                            id: avatarRect
                            width: 48
                            height: 48
                            radius: width / 2
                            color: Appearance.colors.colPrimaryContainer

                            Image {
                                id: avatarImage
                                anchors.fill: parent
                                source: Config.options.profile.avatarPath !== "" 
                                    ? "file://" + Config.options.profile.avatarPicture 
                                    : "file:///home/" + (Quickshell.env("USER") ?? "user") + "/.face"
                                sourceSize.width: avatarImage.width * 2
                                sourceSize.height: avatarImage.height * 2
                                fillMode: Image.PreserveAspectCrop
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: avatarRect.width
                                        height: avatarRect.height
                                        radius: avatarRect.radius
                                    }
                                }
                                onStatusChanged: {
                                    if (status === Image.Error)
                                        visible = false
                                }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "account_circle"
                                iconSize: 32
                                color: Appearance.colors.colOnPrimaryContainer
                                visible: avatarImage.status === Image.Error
                            }
                        }

                        ColumnLayout {
                            spacing: Appearance.spacing.space25
                            Layout.fillWidth: true

                            StyledText {
                                text: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                Layout.maximumWidth: 100
                            }

                            StyledText {
                                id: distroText
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                                Layout.maximumWidth: 100

                                text: {
                                    const d = Config.options.profile.descriptionText
                                    if (d === "::uptime::") return Translation.tr("Up • %1").arg(DateTime.uptime)
                                    return SystemInfo.distroName
                                }
                            }
                        }

                        // Handlers rather than a MouseArea: an item anchored to
                        // fill a layout is undefined behavior, and these are not
                        // items, so the row's layout ignores them.
                        TapHandler {
                            onTapped: root.showingProfile = !root.showingProfile
                        }

                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: -Appearance.spacing.space50
                        height: 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.2; color: Appearance.colors.colOutline }
                            GradientStop { position: 0.8; color: Appearance.colors.colOutline }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.15
                    }

                    RippleButton {
                        id: fab
                        Layout.fillWidth: true
                        implicitHeight: 42
                        property bool justCopied: false
                        buttonText: justCopied ? Translation.tr("Path copied") : Translation.tr("Config file")
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        downAction: () => {
                            Qt.openUrlExternally(`${Directories.config}/illogical-impulse/config.json`);
                        }
                        altAction: () => {
                            Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                            fab.justCopied = true;
                            revertTextTimer.restart()
                        }
                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Appearance.spacing.space150
                            anchors.rightMargin: Appearance.spacing.space150
                            spacing: Appearance.spacing.space100

                            MaterialSymbol {
                                text: fab.justCopied ? "check" : "edit"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: navRail.expanded
                                text: fab.buttonText
                                color: Appearance.colors.colOnSecondaryContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideRight
                            }
                        }
                        Timer {
                            id: revertTextTimer
                            interval: 1500
                            onTriggered: fab.justCopied = false
                        }
                        StyledToolTip {
                            text: Translation.tr("Open the shell config file\nAlternatively right-click to copy path")
                        }
                    }

                    // Scrolls when the tabs don't fit the window height (many
                    // plugins/tabs, short screen); shows nothing extra when they do.
                    StyledFlickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.topMargin: Appearance.spacing.space0
                        Layout.bottomMargin: Appearance.spacing.space100
                        contentHeight: navigationTree.implicitHeight
                        clip: true
                        expressiveScroll: true

                        Column {
                            id: navigationTree
                            width: parent.width
                            spacing: Appearance.spacing.space25

                            Repeater {
                                model: root.pages
                                Column {
                                    id: pageBranch
                                    required property var modelData
                                    required property int index
                                    property bool branchExpanded: index === root.currentPage
                                    width: navigationTree.width
                                    visible: root.pageMatches(index, modelData)
                                    spacing: Appearance.spacing.space25

                                    Connections {
                                        target: root
                                        function onCurrentPageChanged() {
                                            if (root.currentPage === pageBranch.index)
                                                pageBranch.branchExpanded = true
                                        }
                                    }

                                    NavigationRailButton {
                                        visible: !navRail.expanded
                                        width: parent.width
                                        toggled: root.currentPage === pageBranch.index && !root.showingProfile
                                        expanded: false
                                        buttonIcon: pageBranch.modelData.icon
                                        buttonIconRotation: pageBranch.modelData.iconRotation || 0
                                        buttonText: pageBranch.modelData.name
                                        showToggledHighlight: false
                                        onPressed: root.navigateTo(pageBranch.index, "")
                                    }

                                    RippleButton {
                                        visible: navRail.expanded
                                        width: parent.width
                                        implicitHeight: 42
                                        buttonRadius: Appearance.rounding.full
                                        toggled: root.currentPage === pageBranch.index && !root.showingProfile
                                        colBackground: "transparent"
                                        colBackgroundToggled: CF.ColorUtils.transparentize(
                                            Appearance.colors.colPrimary, 0.88)
                                        colBackgroundHover: Appearance.colors.colLayer1Hover
                                        colBackgroundToggledHover: CF.ColorUtils.transparentize(
                                            Appearance.colors.colPrimary, 0.78)
                                        colRipple: Appearance.colors.colLayer1Active
                                        colRippleToggled: Appearance.colors.colLayer1Active
                                        onClicked: {
                                            pageBranch.branchExpanded = !pageBranch.branchExpanded
                                            root.navigateTo(pageBranch.index, "")
                                        }

                                        contentItem: RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Appearance.spacing.space100
                                            anchors.rightMargin: Appearance.spacing.space100
                                            spacing: Appearance.spacing.space100

                                            MaterialSymbol {
                                                text: pageBranch.modelData.icon
                                                rotation: pageBranch.modelData.iconRotation || 0
                                                iconSize: Appearance.font.pixelSize.larger
                                                fill: root.currentPage === pageBranch.index ? 1 : 0
                                                color: root.currentPage === pageBranch.index
                                                    ? Appearance.colors.colPrimary
                                                    : Appearance.colors.colOnLayer1
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: pageBranch.modelData.name
                                                color: root.currentPage === pageBranch.index
                                                    ? Appearance.colors.colPrimary
                                                    : Appearance.colors.colOnLayer1
                                                font.weight: root.currentPage === pageBranch.index ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
                                            }
                                            MaterialSymbol {
                                                visible: pageBranch.modelData.sections.length > 0
                                                text: "expand_more"
                                                rotation: (pageBranch.branchExpanded || root.navigationQuery.length > 0) ? 180 : 0
                                                iconSize: Appearance.font.pixelSize.large
                                                color: Appearance.colors.colSubtext
                                                Behavior on rotation {
                                                    NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                                }
                                            }
                                        }
                                    }

                                    Revealer {
                                        id: sectionRevealer
                                        vertical: true
                                        reveal: navRail.expanded && (pageBranch.branchExpanded || root.navigationQuery.length > 0)
                                        width: parent.width
                                        opacity: reveal ? 1 : 0

                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: Appearance.animation.elementMoveEnter.duration
                                                easing.type: Appearance.animation.elementMoveEnter.type
                                                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                                            }
                                        }

                                        Column {
                                            width: sectionRevealer.width
                                            spacing: Appearance.spacing.space25

                                            Repeater {
                                                model: pageBranch.modelData.sections

                                                RippleButton {
                                                    id: sectionButton
                                                    required property var modelData
                                                    width: pageBranch.width
                                                    implicitHeight: 34
                                                    visible: root.sectionMatches(pageBranch.index, modelData)
                                                    buttonRadius: Appearance.rounding.full
                                                    toggled: root.sectionIsActive(pageBranch.index, modelData)
                                                    colBackground: "transparent"
                                                    colBackgroundToggled: "transparent"
                                                    colBackgroundHover: Appearance.colors.colLayer1Hover
                                                    colBackgroundToggledHover: Appearance.colors.colLayer1Hover
                                                    colRipple: Appearance.colors.colLayer1Active
                                                    colRippleToggled: Appearance.colors.colLayer1Active
                                                    onClicked: root.navigateTo(pageBranch.index, modelData)

                                                    contentItem: RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: Appearance.spacing.space500
                                                        anchors.rightMargin: Appearance.spacing.space100
                                                        spacing: Appearance.spacing.space75
                                                        Rectangle {
                                                            implicitWidth: 5
                                                            implicitHeight: 5
                                                            radius: Appearance.rounding.full
                                                            color: sectionButton.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                                                        }
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: modelData
                                                            color: sectionButton.toggled
                                                                ? Appearance.colors.colPrimary
                                                                : Appearance.colors.colOnLayer1
                                                            font.pixelSize: Appearance.font.pixelSize.small
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut

                Item {
                    anchors.fill: parent

                    Repeater {
                        id: pagesRepeater
                        model: root.pages
                        Loader {
                            id: pageLoader
                            required property var modelData
                            required property var index
                            source: modelData.component

                            active: Config.ready && (root.currentPage === index || item !== null)

                            anchors.fill: parent

                            property bool isActive: root.currentPage === index && !root.showingProfile
                            opacity: isActive ? 1 : 0
                            enabled: isActive
                            visible: isActive
                            anchors.topMargin: isActive ? 0 : Appearance.spacing.space150

                            onLoaded: {
                                if (root.currentPage === index) {
                                    GlobalStates.currentPageInstance = item;
                                }
                            }

                            onIsActiveChanged: {
                                if (isActive && item) {
                                    GlobalStates.currentPageInstance = item;
                                    root.selectedSection = item.currentSection || "";
                                } else if (!isActive && GlobalStates.currentPageInstance === item) {
                                    GlobalStates.currentPageInstance = null;
                                }
                            }

                            Connections {
                                target: pageLoader.item
                                function onCurrentSectionChanged() {
                                    if (pageLoader.isActive)
                                        root.selectedSection = pageLoader.item.currentSection || ""
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
                            }
                            Behavior on anchors.topMargin {
                                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Loader {
                        id: profileLoader
                        active: false
                        anchors.fill: parent
                        source: Qt.resolvedUrl("pages/Profile.qml")

                        property bool isActive: root.showingProfile
                        opacity: isActive ? 1 : 0
                        enabled: isActive
                        visible: isActive
                        anchors.topMargin: isActive ? 0 : Appearance.spacing.space150

                        onIsActiveChanged: {
                            if (isActive && item) {
                                GlobalStates.currentPageInstance = item;
                            } else if (!isActive && GlobalStates.currentPageInstance === item) {
                                GlobalStates.currentPageInstance = null;
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
                        }
                        Behavior on anchors.topMargin {
                            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }
    }

    // Window-level host for the plugin delete confirmation. It fills the whole
    // settings window (the pages themselves are clipping flickables and cannot
    // hold a modal), and is driven purely by PluginManager.pendingUninstallId
    // so the Plugins page only has to request a removal.
    Loader {
        id: uninstallDialogLoader
        anchors.fill: parent
        active: false
        readonly property bool wanted: PluginManager.pendingUninstallId !== ""

        onWantedChanged: if (wanted) active = true
        onActiveChanged: if (active && item) item.forceActiveFocus()
        sourceComponent: PluginUninstallDialog {}

        Binding {
            target: uninstallDialogLoader.item
            property: "show"
            value: uninstallDialogLoader.wanted
            when: uninstallDialogLoader.item !== null
        }

        Connections {
            target: uninstallDialogLoader.item
            function onDismiss() { PluginManager.cancelUninstall(); }
            // Keep the loader alive through the close animation, then release it.
            function onVisibleChanged() {
                if (uninstallDialogLoader.item && !uninstallDialogLoader.item.visible
                        && !uninstallDialogLoader.wanted)
                    uninstallDialogLoader.active = false;
            }
        }
    }
}
