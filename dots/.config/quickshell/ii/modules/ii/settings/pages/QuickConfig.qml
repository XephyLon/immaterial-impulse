import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import Quickshell.Hyprland

ContentPage {
    id: page
    forceWidth: true
    baseWidth: 720
    bottomContentPadding: 35

    function themeArguments(extraArguments) {
        const commandArguments = [Directories.wallpaperSwitchScriptPath, "--noswitch", "--coloronly"]
        const artwork = WallpaperEngine.activeArtwork
        if (artwork && artwork.length > 0)
            commandArguments.push("--image", artwork)
        if (extraArguments) {
            for (let index = 0; index < extraArguments.length; ++index)
                commandArguments.push(extraArguments[index])
        }
        return commandArguments
    }

    function refreshTheme(extraArguments) {
        Quickshell.execDetached(themeArguments(extraArguments))
    }

    function goTo(term) {
        const t = term.toLowerCase().trim()
        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) return child
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

    component SmallLightDarkPreferenceButton: RippleButton {
        id: smallLightDarkPreferenceButton
        required property bool dark
        property color colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        padding: Appearance.spacing.space100
        Layout.fillWidth: true
        Layout.fillHeight: true
        toggled: Appearance.m3colors.darkmode === dark
        colBackground: Appearance.colors.colLayer2
        onClicked: {
            page.refreshTheme(["--mode", dark ? "dark" : "light"])
        }
        contentItem: Item {
            anchors.centerIn: parent
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 30
                    text: dark ? "dark_mode" : "light_mode"
                    color: smallLightDarkPreferenceButton.colText
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: dark ? Translation.tr("Dark") : Translation.tr("Light")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: smallLightDarkPreferenceButton.colText
                }
            }
        }
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Appearance.spacing.space200

        ContentSection {
            icon: "screenshot_monitor"
            title: Translation.tr("Wallpaper & Colors")
            shape: MaterialShape.Shape.Puffy
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space50

                Rectangle {
                    Layout.preferredWidth: 420
                    Layout.preferredHeight: 280
                    radius: Appearance.rounding.large - 3
                    color: Appearance.colors.colLayer2
                    clip: true

                    StyledImage {
                        anchors.fill: parent
                        sourceSize.width: 420
                        sourceSize.height: 280
                        fillMode: Image.PreserveAspectCrop
                        // WE-aware artwork; a video wallpaper falls back to its
                        // generated thumbnail (a raw video path can't render in
                        // an Image) - upstream vb.
                        source: /\.(mp4|webm|mkv|avi|mov)$/i.test(WallpaperEngine.activeArtwork)
                            ? Config.options.background.thumbnailPath
                            : WallpaperEngine.activeArtwork
                        cache: false
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: 420; height: 280
                                radius: Appearance.rounding.large - 3
                            }
                        }
                    }

                    ToolbarPairedFab {
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: Appearance.spacing.space100
                        iconText: "colorize"
                        onClicked: {
                            page.refreshTheme(["--color"])
                        }
                        StyledToolTip {
                            text: "Change accent color"
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space50

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Appearance.spacing.space25
                        uniformCellSizes: true
                        SmallLightDarkPreferenceButton { dark: false }
                        SmallLightDarkPreferenceButton { dark: true }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        rowSpacing: Appearance.spacing.space25
                        columnSpacing: Appearance.spacing.space25

                        Repeater {
                            model: [
                                { value: "auto",               displayName: Translation.tr("Auto"),        icon: "auto_awesome" },
                                { value: "scheme-content",     displayName: Translation.tr("Content"),     icon: "image" },
                                { value: "scheme-expressive",  displayName: Translation.tr("Expressive"),  icon: "palette" },
                                { value: "scheme-fidelity",    displayName: Translation.tr("Fidelity"),    icon: "equal" },
                                { value: "scheme-fruit-salad", displayName: Translation.tr("Fruit Salad"), icon: "nutrition" },
                                { value: "scheme-monochrome",  displayName: Translation.tr("Monochrome"),  icon: "invert_colors" },
                                { value: "scheme-neutral",     displayName: Translation.tr("Neutral"),     icon: "tonality" },
                                { value: "scheme-rainbow",     displayName: Translation.tr("Rainbow"),     icon: "gradient" },
                                { value: "scheme-tonal-spot",  displayName: Translation.tr("Tonal Spot"),  icon: "lens" },
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: width * 0.6
                                radius: Appearance.rounding.normal

                                property bool isSelected: Config.options.appearance.palette.type === modelData.value
                                property bool hovered: hoverArea.containsMouse

                                color: isSelected ? Appearance.colors.colPrimary 
                                    : hovered ? Appearance.colors.colSecondaryContainerHover 
                                    : Appearance.colors.colSecondaryContainer

                                MaterialSymbol {
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.margins: Appearance.spacing.space100
                                    text: modelData.icon
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: parent.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                                }

                                StyledText {
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right
                                    anchors.margins: Appearance.spacing.space100
                                    text: modelData.displayName
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: parent.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                                }

                                MouseArea {
                                    id: hoverArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Config.options.appearance.palette.type = modelData.value
                                        page.refreshTheme(["--type", modelData.value])
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ConfigRow {
                ConfigSwitch {
                    buttonIcon: "motion_mode"
                    text: Translation.tr("Transparency")
                    checked: Config.options.appearance.transparency.enable
                    onCheckedChanged: { Config.options.appearance.transparency.enable = checked; }
                }
                ConfigSwitch {
                    buttonIcon: "autofps_select"
                    enabled: Config.options.appearance.transparency.enable
                    text: Translation.tr("Automatic")
                    checked: Config.options.appearance.transparency.automatic
                    onCheckedChanged: { Config.options.appearance.transparency.automatic = checked; }
                }
            }

            ConfigSelectionArray {
                icon: "brightness_auto"
                text: Translation.tr("Auto dark/light")
                currentValue: Config.options.appearance.autoTheme.mode
                onSelected: newValue => { Config.options.appearance.autoTheme.mode = newValue; }
                options: [
                    { displayName: Translation.tr("Off"),     icon: "close",         value: "off" },
                    { displayName: Translation.tr("Sunset"),  icon: "wb_twilight",   value: "sunset" },
                    { displayName: Translation.tr("Fixed"),   icon: "schedule",      value: "fixed" }
                ]
            }

            ConfigRow {
                visible: Config.options.appearance.autoTheme.mode === "fixed"

                ConfigTextArea {
                    buttonIcon: "light_mode"
                    text: Translation.tr("Light at")
                    placeholderText: "07:00"
                    fieldWidth: 90
                    singleLine: true
                    value: Config.options.appearance.autoTheme.lightTime
                    onValueChanged: {
                        if (value.trim() !== "")
                            Config.options.appearance.autoTheme.lightTime = value.trim();
                    }
                }
                ConfigTextArea {
                    buttonIcon: "dark_mode"
                    text: Translation.tr("Dark at")
                    placeholderText: "19:00"
                    fieldWidth: 90
                    singleLine: true
                    value: Config.options.appearance.autoTheme.darkTime
                    onValueChanged: {
                        if (value.trim() !== "")
                            Config.options.appearance.autoTheme.darkTime = value.trim();
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "lightbulb"
                text: Translation.tr("Sync RGB devices (OpenRGB)")
                description: OpenRgb.available
                    ? Translation.tr("Applies the accent color to your RGB hardware whenever the palette changes")
                    : Translation.tr("The openrgb command was not found — install OpenRGB to use this")
                checked: Config.options.appearance.openrgb.enable
                onCheckedChanged: {
                    Config.options.appearance.openrgb.enable = checked;
                }
            }

            ConfigSelectionArray {
                visible: Config.options.appearance.openrgb.enable && OpenRgb.available
                icon: "palette"
                text: Translation.tr("Light color source")
                currentValue: Config.options.appearance.openrgb.colorSource
                onSelected: newValue => { Config.options.appearance.openrgb.colorSource = newValue; }
                options: [
                    { displayName: Translation.tr("Accent"),  icon: "colors",  value: "accent" },
                    { displayName: Translation.tr("Monitor"), icon: "monitor", value: "monitor" }
                ]
            }

            ColumnLayout {
                visible: Config.options.appearance.openrgb.enable && OpenRgb.available
                    && Config.options.appearance.openrgb.colorSource === "monitor"
                Layout.fillWidth: true
                spacing: 0

                ConfigSwitch {
                    buttonIcon: "fullscreen"
                    text: Translation.tr("Only while fullscreen")
                    description: OpenRgb.grimAvailable || !OpenRgb.monitorMode
                        ? Translation.tr("Follow the screen only while a fullscreen app runs; otherwise use the accent")
                        : Translation.tr("The grim command was not found — install grim to sample the monitor")
                    checked: Config.options.appearance.openrgb.monitorFullscreenOnly
                    onCheckedChanged: {
                        Config.options.appearance.openrgb.monitorFullscreenOnly = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "blur_on"
                    text: Translation.tr("Smooth transitions")
                    description: Translation.tr("Blend toward the sampled color instead of snapping on scene cuts")
                    checked: Config.options.appearance.openrgb.monitorSmooth
                    onCheckedChanged: {
                        Config.options.appearance.openrgb.monitorSmooth = checked;
                    }
                }

                ConfigSwitch {
                    id: gpuAmbientSwitch
                    readonly property bool gpuIncluded: !(Config.options.appearance.openrgb.monitorExcludedTypes ?? []).includes("GPU")
                    buttonIcon: "developer_board"
                    text: Translation.tr("Include GPU lighting")
                    description: Translation.tr("GPU RGB writes ride the graphics i2c bus and can stutter games — off is safer")
                    checked: gpuIncluded
                    onCheckedChanged: {
                        if (checked === gpuIncluded)
                            return;
                        // Whole-list assignment: JsonAdapter lists only
                        // persist when replaced, never when mutated.
                        let types = (Config.options.appearance.openrgb.monitorExcludedTypes ?? []).filter(t => t !== "GPU");
                        if (!checked)
                            types = types.concat(["GPU"]);
                        Config.options.appearance.openrgb.monitorExcludedTypes = types;
                    }

                    Binding {
                        target: gpuAmbientSwitch
                        property: "checked"
                        value: gpuAmbientSwitch.gpuIncluded
                        restoreMode: Binding.RestoreBinding
                    }
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Sample interval (ms)")
                    value: Config.options.appearance.openrgb.monitorPollInterval
                    from: 100
                    to: 2000
                    stepSize: 50
                    onValueChanged: {
                        Config.options.appearance.openrgb.monitorPollInterval = value;
                    }
                }
            }

            ColumnLayout {
                id: openRgbDevices
                visible: Config.options.appearance.openrgb.enable && OpenRgb.available
                Layout.fillWidth: true
                spacing: 0

                // Identical hardware repeats in the raw list (two RAM sticks,
                // multi-controller GPUs); exclusion is name-keyed, so collapse
                // duplicates into one row.
                readonly property var uniqueDevices: {
                    const seen = {};
                    const out = [];
                    for (const dev of OpenRgb.devices) {
                        if (seen[dev.name]) {
                            seen[dev.name].count++;
                            continue;
                        }
                        const entry = { name: dev.name, type: dev.type, count: 1 };
                        seen[dev.name] = entry;
                        out.push(entry);
                    }
                    return out;
                }

                function iconFor(type) {
                    switch (type) {
                    case "DRAM": return "memory";
                    case "GPU": return "developer_board";
                    case "Motherboard": return "developer_board";
                    case "Keyboard": return "keyboard";
                    case "Mouse": return "mouse";
                    case "Gamepad": return "sports_esports";
                    case "Headset": return "headset";
                    case "Cooler": return "mode_fan";
                    case "LED Strip": return "fluorescent";
                    default: return "lightbulb";
                    }
                }

                // Enumeration does a full hardware detection pass when no
                // OpenRGB server runs - scan lazily when the list first shows.
                onVisibleChanged: {
                    if (visible && OpenRgb.devices.length === 0)
                        OpenRgb.rescanDevices();
                }
                Component.onCompleted: {
                    if (visible && OpenRgb.devices.length === 0)
                        OpenRgb.rescanDevices();
                }

                Repeater {
                    model: openRgbDevices.uniqueDevices

                    delegate: ConfigSwitch {
                        id: deviceSwitch
                        required property var modelData
                        readonly property bool syncedNow: !(Config.options.appearance.openrgb.excludedDevices ?? []).includes(modelData.name)

                        buttonIcon: openRgbDevices.iconFor(modelData.type)
                        text: modelData.name
                        description: modelData.count > 1
                            ? Translation.tr("%1 — %2 devices").arg(modelData.type).arg(modelData.count)
                            : modelData.type
                        checked: syncedNow
                        onCheckedChanged: {
                            if (checked === syncedNow)
                                return;
                            // Whole-list assignment: JsonAdapter lists only
                            // persist when replaced, never when mutated.
                            let excluded = (Config.options.appearance.openrgb.excludedDevices ?? []).filter(n => n !== modelData.name);
                            if (!checked)
                                excluded = excluded.concat([modelData.name]);
                            Config.options.appearance.openrgb.excludedDevices = excluded;
                        }

                        // Re-sync the switch with config after external edits
                        // without losing the binding on manual toggles.
                        Binding {
                            target: deviceSwitch
                            property: "checked"
                            value: deviceSwitch.syncedNow
                            restoreMode: Binding.RestoreBinding
                        }
                    }
                }

                RippleButtonWithIcon {
                    Layout.alignment: Qt.AlignRight
                    Layout.topMargin: Appearance.spacing.space100
                    materialIcon: "refresh"
                    enabled: !OpenRgb.scanning
                    mainText: OpenRgb.scanning
                        ? Translation.tr("Scanning devices...")
                        : (OpenRgb.devices.length === 0
                            ? Translation.tr("Scan for devices")
                            : Translation.tr("Rescan devices"))
                    onClicked: OpenRgb.rescanDevices()
                }
            }
        }

        ContentSection {
            icon: "screenshot_monitor"
            title: Translation.tr("Bar & Screen")
            shape: MaterialShape.Shape.ClamShell
            Layout.fillWidth: true

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: Appearance.spacing.space100
                columnSpacing: Appearance.spacing.space100

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: barPosCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: Appearance.borderWidth.standard
                    border.color: "transparent"

                    ColumnLayout {
                        id: barPosCol
                        anchors { fill: parent; margins: Appearance.spacing.space150 }
                        spacing: Appearance.spacing.space100

                        RowLayout {
                            spacing: Appearance.spacing.space100
                            MaterialSymbol {
                                text: "swap_vert"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: Translation.tr("Bar position")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: barPosArray
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignRight
                            currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                            onSelected: newValue => {
                                Config.options.bar.bottom = (newValue & 1) !== 0;
                                Config.options.bar.vertical = (newValue & 2) !== 0;
                            }
                            options: [
                                { displayName: Translation.tr("Top"), icon: "arrow_upward",   value: 0 },
                                { displayName: Translation.tr("Left"), icon: "arrow_back",     value: 2 },
                                { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 },
                                { displayName: Translation.tr("Right"), icon: "arrow_forward",  value: 3 }
                            ]
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: barStyleCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: Appearance.borderWidth.standard
                    border.color: "transparent"

                    ColumnLayout {
                        id: barStyleCol
                        anchors { fill: parent; margins: Appearance.spacing.space150 }
                        spacing: Appearance.spacing.space100

                        RowLayout {
                            spacing: Appearance.spacing.space100
                            MaterialSymbol {
                                text: "settop_component"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: Translation.tr("Bar style")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: barStyleArray
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignRight
                            currentValue: Config.options.bar.cornerStyle
                            onSelected: newValue => { Config.options.bar.cornerStyle = newValue; }
                            options: [
                                { displayName: Translation.tr("Hug"), icon: "line_curve", value: 0 },
                                { displayName: Translation.tr("Float"), icon: "view_day",   value: 1 },
                                { displayName: Translation.tr("Islands"), icon: "crop_3_2",   value: 2 },
                                { displayName: Translation.tr("M3"), icon: "interests",  value: 3 }
                            ]
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: screenRoundCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    ColumnLayout {
                        id: groupStyleCol
                        anchors { fill: parent; margins: Appearance.spacing.space150 }
                        spacing: Appearance.spacing.space100

                        RowLayout {
                            spacing: Appearance.spacing.space100
                            MaterialSymbol {
                                text: "tab_group"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: Translation.tr("Group style")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: groupStyleArray
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignRight
                            currentValue: Config.options.bar.borderless
                            onSelected: newValue => { Config.options.bar.borderless = newValue; }
                            options: [
                                { displayName: Translation.tr("No"),          icon: "close",         value: "transparent" },
                                { displayName: Translation.tr("Pills"),     icon: "pill",          value: "pills" },
                                { displayName: Translation.tr("Separated"), icon: "view_column_2", value: "separated" }
                            ]
                        }
                    }
                    
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: groupStyleCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: screenRoundCol
                        anchors { fill: parent; margins: Appearance.spacing.space150 }
                        spacing: Appearance.spacing.space100

                        RowLayout {
                            spacing: Appearance.spacing.space100
                            MaterialSymbol {
                                text: "rounded_corner"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: Translation.tr("Screen round corner")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: screenRoundArray
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignRight
                            currentValue: Config.options.appearance.fakeScreenRounding
                            onSelected: newValue => { Config.options.appearance.fakeScreenRounding = newValue; }
                            options: [
                                { displayName: Translation.tr("No"),                  icon: "close",           value: 0 },
                                { displayName: Translation.tr("Yes"),                 icon: "check",           value: 1 },
                                { displayName: Translation.tr("When not fullscreen"), icon: "fullscreen_exit", value: 2 }
                            ]
                        }
                    }
                }
            }
        }
    }
}
