import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

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

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Appearance.spacing.space200

        ContentSection {
            icon: "splitscreen_left"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Left Sidebar")

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: mediaCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: Appearance.borderWidth.standard
                    border.color: "transparent"

                    ColumnLayout {
                        id: mediaCol
                        anchors { fill: parent; margins: Appearance.spacing.space150 }
                        spacing: Appearance.spacing.space100

                        MaterialSymbol {
                            text: "music_note"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Media Player")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }
                        Item { Layout.fillHeight: true }
                        GroupedList {
                            Layout.fillWidth: true
                            bgcolor: Appearance.colors.colLayer2
                            ConfigSwitch {
                                buttonIcon: "check"
                                text: Translation.tr("Enable")
                                checked: Config.options.sidebar.media.enable
                                onToggleRequested: Config.options.sidebar.media.enable = !Config.options.sidebar.media.enable
                            }
                            ConfigSwitch {
                                buttonIcon: "radio_button_partial"
                                text: Translation.tr("Follow Album Colors")
                                checked: Config.options.sidebar.media.artColors
                                onToggleRequested: Config.options.sidebar.media.artColors = !Config.options.sidebar.media.artColors
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space100

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: aiCol.implicitHeight + 24
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        border.width: Appearance.borderWidth.standard
                        border.color: "transparent"

                        ColumnLayout {
                            id: aiCol
                            anchors { fill: parent; margins: Appearance.spacing.space150 }
                            spacing: Appearance.spacing.space100

                            MaterialSymbol {
                                text: "smart_toy"
                                iconSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr("AI")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            ConfigSelectionArray {
                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight
                                currentValue: Config.options.policies.ai
                                onSelected: newValue => { Config.options.policies.ai = newValue }
                                options: [
                                    { displayName: Translation.tr("No"), icon: "close", value: 0 },
                                    { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                                    { displayName: Translation.tr("Local"), icon: "sync_saved_locally", value: 2 }
                                ]
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: weebCol.implicitHeight + 24
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        border.width: Appearance.borderWidth.standard
                        border.color: "transparent"

                        ColumnLayout {
                            id: weebCol
                            anchors { fill: parent; margins: Appearance.spacing.space150 }
                            spacing: Appearance.spacing.space100

                            MaterialSymbol {
                                text: "playing_cards"
                                iconSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr("Weeb")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            ConfigSelectionArray {
                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight
                                currentValue: Config.options.policies.weeb
                                onSelected: newValue => { Config.options.policies.weeb = newValue }
                                options: [
                                    { displayName: Translation.tr("No"), icon: "close", value: 0 },
                                    { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                                    { displayName: Translation.tr("Closet"), icon: "ev_shadow", value: 2 }
                                ]
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Appearance.spacing.space50
                implicitHeight: translatorCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: Appearance.borderWidth.standard
                border.color: "transparent"

                ColumnLayout {
                    id: translatorCol
                    anchors { fill: parent; margins: Appearance.spacing.space150 }
                    spacing: Appearance.spacing.space100

                    RowLayout {
                        spacing: Appearance.spacing.space100
                        ConfigSwitch {
                            buttonIcon: "translate"
                            text: Translation.tr("Enable Translator")
                            checked: Config.options.sidebar.translator.enable
                            onToggleRequested: Config.options.sidebar.translator.enable = !Config.options.sidebar.translator.enable
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "splitscreen_right"
            shape: MaterialShape.Shape.Slanted
            title: Translation.tr("Right Sidebar")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "planner_banner_ad_pt"
                    text: Translation.tr('Banner')
                    checked: Config.options.sidebar.banner
                    onToggleRequested: Config.options.sidebar.banner = !Config.options.sidebar.banner
                }

                ConfigSwitch {
                    buttonIcon: "music_note"
                    text: Translation.tr('Media Player')
                    checked: Config.options.sidebar.mediaPlayer
                    onToggleRequested: Config.options.sidebar.mediaPlayer = !Config.options.sidebar.mediaPlayer
                }

                ConfigSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr('Keep right sidebar loaded')
                    checked: Config.options.sidebar.keepRightSidebarLoaded
                    onToggleRequested: Config.options.sidebar.keepRightSidebarLoaded = !Config.options.sidebar.keepRightSidebarLoaded
                }
            }

            ContentSubsection {
                title: Translation.tr("Quick toggles")
                GroupedList {
                    ConfigSelectionArray {
                        text: Translation.tr("Style")
                        icon: "toggle_on"
                        Layout.fillWidth: false
                        currentValue: Config.options.sidebar.quickToggles.style
                        onSelected: newValue => {
                            Config.options.sidebar.quickToggles.style = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Classic"),
                                icon: "password_2",
                                value: "classic"
                            },
                            {
                                displayName: Translation.tr("Android"),
                                icon: "action_key",
                                value: "android"
                            }
                        ]
                    }
                    ConfigSpinBox {
                        enabled: Config.options.sidebar.quickToggles.style === "android"
                        icon: "add_column_left"
                        text: Translation.tr("Columns")
                        value: Config.options.sidebar.quickToggles.android.columns
                        from: 1
                        to: 8
                        stepSize: 1
                        onValueModified: {
                            Config.options.sidebar.quickToggles.android.columns = newValue;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Sliders")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.sidebar.quickSliders.enable
                        onToggleRequested: Config.options.sidebar.quickSliders.enable = !Config.options.sidebar.quickSliders.enable
                    }

                    ConfigSwitch {
                        buttonIcon: "brightness_6"
                        text: Translation.tr("Brightness")
                        enabled: Config.options.sidebar.quickSliders.enable
                        checked: Config.options.sidebar.quickSliders.showBrightness
                        onToggleRequested: Config.options.sidebar.quickSliders.showBrightness = !Config.options.sidebar.quickSliders.showBrightness
                    }

                    ConfigSwitch {
                        buttonIcon: "volume_up"
                        text: Translation.tr("Volume")
                        enabled: Config.options.sidebar.quickSliders.enable
                        checked: Config.options.sidebar.quickSliders.showVolume
                        onToggleRequested: Config.options.sidebar.quickSliders.showVolume = !Config.options.sidebar.quickSliders.showVolume
                    }

                    ConfigSwitch {
                        buttonIcon: "mic"
                        text: Translation.tr("Microphone")
                        enabled: Config.options.sidebar.quickSliders.enable
                        checked: Config.options.sidebar.quickSliders.showMic
                        onToggleRequested: Config.options.sidebar.quickSliders.showMic = !Config.options.sidebar.quickSliders.showMic
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Corner open")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.sidebar.cornerOpen.enable
                        onToggleRequested: Config.options.sidebar.cornerOpen.enable = !Config.options.sidebar.cornerOpen.enable
                    }
                    ConfigSwitch {
                        buttonIcon: "highlight_mouse_cursor"
                        text: Translation.tr("Hover to trigger")
                        checked: Config.options.sidebar.cornerOpen.clickless
                        onToggleRequested: Config.options.sidebar.cornerOpen.clickless = !Config.options.sidebar.cornerOpen.clickless
                    }
                    ConfigSwitch {
                        buttonIcon: "vertical_align_bottom"
                        text: Translation.tr("Place at bottom")
                        checked: Config.options.sidebar.cornerOpen.bottom
                        onToggleRequested: Config.options.sidebar.cornerOpen.bottom = !Config.options.sidebar.cornerOpen.bottom
                    }
                    ConfigSwitch {
                        buttonIcon: "unfold_more_double"
                        text: Translation.tr("Value scroll")
                        checked: Config.options.sidebar.cornerOpen.valueScroll
                        onToggleRequested: Config.options.sidebar.cornerOpen.valueScroll = !Config.options.sidebar.cornerOpen.valueScroll
                    }
                    ConfigSwitch {
                        buttonIcon: "visibility"
                        text: Translation.tr("Visualize region")
                        checked: Config.options.sidebar.cornerOpen.visualize
                        onToggleRequested: Config.options.sidebar.cornerOpen.visualize = !Config.options.sidebar.cornerOpen.visualize
                    }
                    ConfigSwitch {
                        enabled: Config.options.sidebar.cornerOpen.clickless
                        buttonIcon: "ads_click"
                        text: Translation.tr("Force hover at absolute corner")
                        checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                        onToggleRequested: Config.options.sidebar.cornerOpen.clicklessCornerEnd = !Config.options.sidebar.cornerOpen.clicklessCornerEnd
                    }
                    ConfigSpinBox {
                        enabled: Config.options.sidebar.cornerOpen.clickless
                        icon: "arrow_cool_down"
                        text: Translation.tr("Vertical offset")
                        value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                        from: 0; to: 20; stepSize: 1
                        onValueModified: { Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = newValue }
                    }
                    ConfigSpinBox {
                        icon: "arrow_range"
                        text: Translation.tr("Region width")
                        value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                        from: 1; to: 300; stepSize: 1
                        onValueModified: { Config.options.sidebar.cornerOpen.cornerRegionWidth = newValue }
                    }
                    ConfigSpinBox {
                        icon: "height"
                        text: Translation.tr("Region height")
                        value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                        from: 1; to: 300; stepSize: 1
                        onValueModified: { Config.options.sidebar.cornerOpen.cornerRegionHeight = newValue }
                    }
                }
            }
        }

        ContentSection { // I see that for many the overview is important, I put it first why not
            icon: "overview_key"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Overview")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.overview.enable
                    onToggleRequested: Config.options.overview.enable = !Config.options.overview.enable
                }
                ConfigSwitch {
                    buttonIcon: "center_focus_strong"
                    text: Translation.tr("Center icons")
                    checked: Config.options.overview.centerIcons
                    onToggleRequested: Config.options.overview.centerIcons = !Config.options.overview.centerIcons
                }
                ConfigSpinBox {
                    icon: "loupe"
                    text: Translation.tr("Scale (%)")
                    value: Config.options.overview.scale * 100
                    from: 1
                    to: 100
                    stepSize: 1
                    onValueModified: {
                        Config.options.overview.scale = newValue / 100;
                    }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Style")
                    icon: "style"
                    currentValue: Config.options.overview.style
                    onSelected: newValue => {
                        Config.options.overview.style = newValue
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "grid_on",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Niri Like"),
                            icon: "swap_horiz",
                            value: "niri"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Default Settings")
                visible: Config.options.overview.style !== "niri"

                GroupedList {
                    visible: Config.options.overview.style !== "niri"
                    ConfigRow {
                        uniform: true
                        visible: Config.options.overview.style !== "niri"
                        ConfigSpinBox {
                            icon: "splitscreen_bottom"
                            text: Translation.tr("Rows")
                            value: Config.options.overview.rows
                            from: 1
                            to: 20
                            stepSize: 1
                            onValueModified: {
                                Config.options.overview.rows = newValue;
                            }
                        }
                        ConfigSpinBox {
                            icon: "splitscreen_right"
                            text: Translation.tr("Columns")
                            value: Config.options.overview.columns
                            from: 1
                            to: 20
                            stepSize: 1
                            onValueModified: {
                                Config.options.overview.columns = newValue;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        visible: Config.options.overview.style !== "niri"
                        Layout.alignment: Qt.AlignHCenter
                        Layout.leftMargin: Appearance.spacing.space300
                        ConfigSelectionArray {
                            Layout.alignment: Qt.AlignHCenter
                            currentValue: Config.options.overview.orderRightLeft
                            onSelected: newValue => {
                                Config.options.overview.orderRightLeft = newValue
                            }
                            options: [
                                {
                                    displayName: Translation.tr("Left to right"),
                                    icon: "arrow_forward",
                                    value: 0
                                },
                                {
                                    displayName: Translation.tr("Right to left"),
                                    icon: "arrow_back",
                                    value: 1
                                }
                            ]
                        }
                        ConfigSelectionArray {
                            Layout.alignment: Qt.AlignHCenter
                            currentValue: Config.options.overview.orderBottomUp
                            onSelected: newValue => {
                                Config.options.overview.orderBottomUp = newValue
                            }
                            options: [
                                {
                                    displayName: Translation.tr("Top-down"),
                                    icon: "arrow_downward",
                                    value: 0
                                },
                                {
                                    displayName: Translation.tr("Bottom-up"),
                                    icon: "arrow_upward",
                                    value: 1
                                }
                            ]
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "select_window"
            shape: MaterialShape.Shape.SoftBurst
            title: Translation.tr("Overlay")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "high_density"
                    text: Translation.tr("Enable opening zoom animation")
                    checked: Config.options.overlay.openingZoomAnimation
                    onToggleRequested: Config.options.overlay.openingZoomAnimation = !Config.options.overlay.openingZoomAnimation
                }
                ConfigSwitch {
                    buttonIcon: "texture"
                    text: Translation.tr("Darken screen")
                    checked: Config.options.overlay.darkenScreen
                    onToggleRequested: Config.options.overlay.darkenScreen = !Config.options.overlay.darkenScreen
                }
            }

            ContentSubsection {
                title: Translation.tr("Floating Image")
                GroupedList {
                    ConfigTextArea {
                        id: floatingImageSourceField
                        Layout.fillWidth: true
                        fieldWidth: 430
                        buttonIcon: "imagesmode"
                        text: Translation.tr("Image source")
                        value: Config.options.overlay.floatingImage.imageSource
                        onValueChanged: {
                            floatingImageSourceDebounceTimer.restart();
                        }

                        Timer {
                            id: floatingImageSourceDebounceTimer
                            interval: 1000
                            repeat: false
                            onTriggered: {
                                Config.options.overlay.floatingImage.imageSource = floatingImageSourceField.value;
                            }
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Crosshair")

                Rectangle {
                    id: crosshairCard
                    Layout.fillWidth: true
                    implicitHeight: crosshairCol.implicitHeight + 28
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: crosshairCol
                        anchors { fill: parent; margins: 14 }
                        spacing: Appearance.spacing.space100

                        ConfigTextArea {
                            id: crosshairCodeField
                            Layout.fillWidth: true
                            buttonIcon: "point_scan"
                            text: Translation.tr("Crosshair code")
                            placeholderText: Translation.tr("Crosshair code (in Valorant's format)")
                            value: Config.options.crosshair.code
                            onValueChanged: {
                                crosshairCodeDebounceTimer.restart();
                            }

                            Timer {
                                id: crosshairCodeDebounceTimer
                                interval: 1000
                                repeat: false
                                onTriggered: {
                                    Config.options.crosshair.code = crosshairCodeField.value;
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.leftMargin: Appearance.spacing.space100
                                Layout.fillWidth: true
                                text: Translation.tr("Press Super+G to open the overlay and pin the crosshair")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.Wrap
                            }
                            RippleButtonWithIcon {
                                id: editorButton
                                Layout.fillWidth: true
                                Layout.rightMargin: Appearance.spacing.space100
                                Layout.preferredHeight: 40
                                buttonRadius: Appearance.rounding.normal
                                materialIcon: "open_in_new"
                                mainText: Translation.tr("Open editor")
                                onClicked: {
                                    Qt.openUrlExternally(`https://www.vcrdb.net/builder?c=${Config.options.crosshair.code}`);
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "voting_chip"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("On-screen display")
            GroupedList {
                ConfigSpinBox {
                    // Reached by name from ConfigControlWriteBackRuntimeTest.qml,
                    // which opens this page against an out-of-range stored value.
                    objectName: "osdTimeoutSpinBox"
                    icon: "av_timer"
                    text: Translation.tr("Timeout (ms)")
                    value: Config.options.osd.timeout
                    from: 100
                    to: 3000
                    stepSize: 100
                    onValueModified: {
                        Config.options.osd.timeout = newValue;
                    }
                }
            }
        }

        ContentSection {
            icon: "shelves"
            title: Translation.tr("Drop shelf")
            shape: MaterialShape.Shape.Cookie4Sided

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "swipe_up"
                    text: Translation.tr("Reveal when dragging files onto the bar")
                    checked: Config.options.dropShelf.dragToBarReveal
                    onToggleRequested: Config.options.dropShelf.dragToBarReveal = !Config.options.dropShelf.dragToBarReveal
                }
                ConfigSwitch {
                    buttonIcon: "gesture"
                    text: Translation.tr("Shake cursor (while dragging) to summon")
                    checked: Config.options.dropShelf.shakeToSummon
                    onToggleRequested: Config.options.dropShelf.shakeToSummon = !Config.options.dropShelf.shakeToSummon
                }
                ConfigSpinBox {
                    enabled: Config.options.dropShelf.shakeToSummon
                    icon: "tune"
                    text: Translation.tr("Shake sensitivity (%)")
                    value: Math.round(Config.options.dropShelf.shakeSensitivity * 100)
                    from: 50
                    to: 300
                    stepSize: 25
                    onValueModified: { Config.options.dropShelf.shakeSensitivity = newValue / 100 }
                }
                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Auto-dismiss after (seconds)")
                    value: Config.options.dropShelf.autoDismissSeconds
                    from: 0
                    to: 60
                    stepSize: 1
                    onValueModified: { Config.options.dropShelf.autoDismissSeconds = newValue }
                }
                ConfigSwitch {
                    buttonIcon: "blur_on"
                    // Both this and the opacity below are inert with transparency
                    // off - the shelf is painted opaque either way - so leaving
                    // them live would only let the user set values nothing reads.
                    enabled: Config.options.appearance.transparency.enable
                    text: Translation.tr("Blur background")
                    checked: Config.options.dropShelf.blurBackground
                    onToggleRequested: Config.options.dropShelf.blurBackground = !Config.options.dropShelf.blurBackground
                }
                ConfigSpinBox {
                    enabled: Config.options.dropShelf.blurBackground
                        && Config.options.appearance.transparency.enable
                    icon: "opacity"
                    text: Translation.tr("Background opacity (%)")
                    value: Math.round(Config.options.dropShelf.backgroundOpacity * 100)
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueModified: { Config.options.dropShelf.backgroundOpacity = newValue / 100 }
                }
            }
        }
    }
}
