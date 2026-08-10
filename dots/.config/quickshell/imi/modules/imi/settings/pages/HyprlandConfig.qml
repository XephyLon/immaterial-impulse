import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import qs.modules.common.functions
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models.hyprland

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

    Component.onCompleted: {
        const h = Config.options.hyprland
        HyprlandConfig.setMany({
            "decoration:rounding":                  h.decoration.rounding,
            "decoration:blur:enabled":              h.decoration.blur.enabled ? 1 : 0,
            "decoration:blur:size":                 h.decoration.blur.size,
            "decoration:blur:passes":               h.decoration.blur.passes,
            "decoration:blur:ignore_opacity":       h.decoration.blur.ignoreOpacity ? 1 : 0,
            "decoration:blur:new_optimizations":    h.decoration.blur.newOptimizations ? 1 : 0,
            "decoration:blur:xray":                 h.decoration.blur.xray ? 1 : 0,
            "decoration:blur:noise":                h.decoration.blur.noise,
            "decoration:blur:contrast":             h.decoration.blur.contrast,
            "decoration:blur:brightness":           h.decoration.blur.brightness,
            "decoration:blur:vibrancy":             h.decoration.blur.vibrancy,
            "decoration:blur:vibrancy_darkness":    h.decoration.blur.vibrancyDarkness,
            "decoration:blur:special":              h.decoration.blur.special ? 1 : 0,
            "decoration:blur:popups":               h.decoration.blur.popups ? 1 : 0,
            "decoration:blur:popups_ignorealpha":   h.decoration.blur.popupsIgnorealpha,
            "decoration:blur:input_methods":        h.decoration.blur.inputMethods ? 1 : 0,
            "decoration:blur:input_methods_ignorealpha": h.decoration.blur.inputMethodsIgnorealpha,
            "decoration:active_opacity":            h.decoration.activeOpacity,
            "decoration:inactive_opacity":          h.decoration.inactiveOpacity,
            "general:border_size":                  h.general.borderSize,
            "general:gaps_in":                      h.general.gapsIn,
            "general:gaps_out":                     h.general.gapsOut,
            "general:layout":                       h.general.layout,
            "animations:enabled":                   h.animations.enable ? 1 : 0,
            "input:kb_layout":                      h.input.kbLayout,
            "input:kb_options":                     h.input.kbOptions,
            "input:numlock_by_default":             h.input.numlock ? 1 : 0,
            "input:repeat_delay":                   h.input.repeatDelay,
            "input:repeat_rate":                    h.input.repeatRate,
            "input:follow_mouse":                   h.input.followMouse,
            "input:touchpad:natural_scroll":        h.input.touchpad.naturalScroll ? 1 : 0,
            "input:touchpad:disable_while_typing":  h.input.touchpad.disableWhileTyping ? 1 : 0,
            "input:touchpad:clickfinger_behavior":  h.input.touchpad.clickfingerBehavior ? 1 : 0,
            "input:touchpad:scroll_factor":         h.input.touchpad.scrollFactor
        })
    }
    MonitorConfigOption { id: monitorConfig }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Appearance.spacing.space250

        // Displays
        ContentSection {
            icon: "monitor"
            shape: MaterialShape.Shape.ClamShell
            title: Translation.tr("Displays")
            visible: monitorConfig.monitors.length > 0

            MonitorCanvas {
                id: monitorCanvas
                Layout.fillWidth: true
                monitorConfig: monitorConfig
            }

            ContentSubsection {
                Layout.topMargin: Appearance.spacing.space150
                title: (monitorConfig.monitors[monitorCanvas.selectedIndex]?.name ?? "")
                    + " · "
                    + (monitorConfig.monitors[monitorCanvas.selectedIndex]?.description ?? "")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "tv_off"
                        text: Translation.tr("Enabled")
                        checked: !(monitorConfig.monitors[monitorCanvas.selectedIndex]?.disabled ?? false)
                        onToggleRequested: {
                            const disabled = monitorConfig.monitors[monitorCanvas.selectedIndex]?.disabled ?? false
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { disabled: !disabled })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                    }

                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "aspect_ratio"
                        text: Translation.tr("Resolution & Refresh Rate")
                        textRole: "display"
                        model: (monitorConfig.monitors[monitorCanvas.selectedIndex]?.availableModes ?? [])
                            .map(mode => ({ display: mode, value: mode }))
                        currentValue: monitorConfig.monitors[monitorCanvas.selectedIndex]?.currentMode ?? ""
                        onSelected: newValue => {
                            const mode = newValue
                            const parts = mode.match(/(\d+)x(\d+)@([\d.]+)Hz/)
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                                currentMode: mode,
                                width: parseInt(parts[1]),
                                height: parseInt(parts[2]),
                                refreshRate: parseFloat(parts[3])
                            })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                    }

                    ConfigSelectionArray {
                        text: Translation.tr("Orientation")
                        icon: "mobile_rotate"
                        currentValue: monitorConfig.monitors[monitorCanvas.selectedIndex]?.transform ?? 0
                        onSelected: newValue => {
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { transform: newValue })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                        options: [
                            { displayName: Translation.tr("Normal"), icon: "screen_rotation_alt", value: 0 },
                            { displayName: "90°",                    icon: "rotate_90_degrees_cw",  value: 1 },
                            { displayName: "180°",                   icon: "screen_rotation",       value: 2 },
                            { displayName: "270°",                   icon: "rotate_90_degrees_ccw", value: 3 },
                        ]
                    }
    
                    ConfigSpinBox {
                        icon: "zoom_in"
                        text: Translation.tr("Scale")
                        value: Math.round((monitorConfig.monitors[monitorCanvas.selectedIndex]?.scale ?? 1.0) * 100)
                        from: 50; to: 300; stepSize: 25
                        onValueModified: {
                            const newVal = newValue / 100.0
                            if (newVal === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.scale ?? 1.0)) return
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { scale: newVal })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                    }

                    ConfigSpinBox {
                        icon: "swap_horiz"
                        text: Translation.tr("Position X")
                        value: monitorConfig.monitors[monitorCanvas.selectedIndex]?.x ?? 0
                        from: 0; to: 7680; stepSize: 1
                        onValueModified: {
                            if (newValue === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.x ?? 0)) return
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { x: newValue })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                    }

                    ConfigSpinBox {
                        icon: "swap_vert"
                        text: Translation.tr("Position Y")
                        value: monitorConfig.monitors[monitorCanvas.selectedIndex]?.y ?? 0
                        from: 0; to: 4320; stepSize: 1
                        onValueModified: {
                            if (newValue === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.y ?? 0)) return
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { y: newValue })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                    }
                }        
            }
        }

        // Layout
        ContentSection {
            icon: "auto_awesome_mosaic"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Layout")

            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Tiling Layout")
                    icon: "responsive_layout"
                    currentValue: Config.options.hyprland.general.layout
                    onSelected: newValue => {
                        Config.options.hyprland.general.layout = newValue
                        HyprlandConfig.set("general:layout", newValue)
                    }
                    options: [
                        { displayName: Translation.tr("Dwindle"),   icon: "browse",             value: "dwindle"   },
                        { displayName: Translation.tr("Master"),    icon: "auto_awesome_mosaic", value: "master"    },
                        { displayName: Translation.tr("Scrolling"), icon: "view_carousel",       value: "scrolling" },
                    ]
                }
            }
        }

        // Input
        ContentSection {
            icon: "trackpad_input"
            shape: MaterialShape.Shape.Pentagon
            title: Translation.tr("Input")

            ContentSubsection {
                title: Translation.tr("Keyboard")

                GroupedList {
                    ConfigTextArea {
                        id: kbLayoutField
                        Layout.fillWidth: true
                        buttonIcon: "keyboard"
                        text: Translation.tr("Keyboard layout")
                        placeholderText: Translation.tr("e.g., us, es, latam")
                        Component.onCompleted: value = Config.options.hyprland.input.kbLayout
                        onValueChanged: kbLayoutDebounceTimer.restart()

                        Timer {
                            id: kbLayoutDebounceTimer
                            interval: 1000
                            repeat: false
                            onTriggered: {
                                Config.options.hyprland.input.kbLayout = kbLayoutField.value
                                HyprlandConfig.set("input:kb_layout", kbLayoutField.value)
                            }
                        }
                    }
                    ConfigSelectionArray {
                        text: Translation.tr("Extra layout switch (xkb)")
                        // Super+Space is a real compositor bind (keybinds.lua) and
                        // always works; it is not offered here because xkb grp:
                        // toggles also fire with extra modifiers held (e.g.
                        // Super+Alt+Space float-toggle would switch layout too).
                        icon: "keyboard_tab"
                        currentValue: Config.options.hyprland.input.kbOptions
                        onSelected: newValue => {
                            Config.options.hyprland.input.kbOptions = newValue
                            HyprlandConfig.set("input:kb_options", newValue)
                        }
                        options: [
                            { displayName: Translation.tr("None"),        icon: "block",     value: "" },
                            { displayName: Translation.tr("Alt+Shift"),   icon: "keyboard",  value: "grp:alt_shift_toggle" },
                        ]
                    }
                    ConfigSwitch {
                        buttonIcon: "numbers"
                        text: Translation.tr("Numlock by default")
                        checked: Config.options.hyprland.input.numlock
                        onToggleRequested: {
                            const next = !Config.options.hyprland.input.numlock
                            Config.options.hyprland.input.numlock = next
                            HyprlandConfig.set("input:numlock_by_default", next ? 1 : 0)
                        }
                    }

                    ConfigSpinBox {
                        icon: "keyboard_return"
                        text: Translation.tr("Repeat delay (ms)")
                        value: Config.options.hyprland.input.repeatDelay
                        from: 100; to: 1000; stepSize: 10
                        onValueModified: {
                            if (newValue === Config.options.hyprland.input.repeatDelay) return
                            Config.options.hyprland.input.repeatDelay = newValue
                            HyprlandConfig.set("input:repeat_delay", newValue)
                        }
                    }

                    ConfigSpinBox {
                        icon: "speed"
                        text: Translation.tr("Repeat rate")
                        value: Config.options.hyprland.input.repeatRate
                        from: 10; to: 100; stepSize: 1
                        onValueModified: {
                            if (newValue === Config.options.hyprland.input.repeatRate) return
                            Config.options.hyprland.input.repeatRate = newValue
                            HyprlandConfig.set("input:repeat_rate", newValue)
                        }
                    }
                    ConfigSelectionArray {
                        text: Translation.tr("Follow mouse")
                        icon: "mouse"
                        currentValue: Config.options.hyprland.input.followMouse
                        onSelected: newValue => {
                            Config.options.hyprland.input.followMouse = newValue
                            HyprlandConfig.set("input:follow_mouse", newValue)
                        }
                        options: [
                            { displayName: Translation.tr("Disabled"), icon: "mouse",     value: 0 },
                            { displayName: Translation.tr("Full"),     icon: "open_with",  value: 1 },
                            { displayName: Translation.tr("Loose"),    icon: "drag_pan",   value: 2 },
                            { displayName: Translation.tr("Explicit"), icon: "ads_click",  value: 3 },
                        ]
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Touchpad")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "swap_vert"
                        text: Translation.tr("Natural scroll")
                        checked: Config.options.hyprland.input.touchpad.naturalScroll
                        onToggleRequested: {
                            const next = !Config.options.hyprland.input.touchpad.naturalScroll
                            Config.options.hyprland.input.touchpad.naturalScroll = next
                            HyprlandConfig.set("input:touchpad:natural_scroll", next ? 1 : 0)
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "keyboard_hide"
                        text: Translation.tr("Disable while typing")
                        checked: Config.options.hyprland.input.touchpad.disableWhileTyping
                        onToggleRequested: {
                            const next = !Config.options.hyprland.input.touchpad.disableWhileTyping
                            Config.options.hyprland.input.touchpad.disableWhileTyping = next
                            HyprlandConfig.set("input:touchpad:disable_while_typing", next ? 1 : 0)
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "touch_app"
                        text: Translation.tr("Clickfinger behavior")
                        checked: Config.options.hyprland.input.touchpad.clickfingerBehavior
                        onToggleRequested: {
                            const next = !Config.options.hyprland.input.touchpad.clickfingerBehavior
                            Config.options.hyprland.input.touchpad.clickfingerBehavior = next
                            HyprlandConfig.set("input:touchpad:clickfinger_behavior", next ? 1 : 0)
                        }
                    }

                    ConfigSpinBox {
                        icon: "swipe"
                        text: Translation.tr("Scroll factor")
                        value: Math.round(Config.options.hyprland.input.touchpad.scrollFactor * 10)
                        from: 1; to: 30; stepSize: 1
                        onValueModified: {
                            const newVal = newValue / 10.0
                            if (newVal === Config.options.hyprland.input.touchpad.scrollFactor) return
                            Config.options.hyprland.input.touchpad.scrollFactor = newVal
                            HyprlandConfig.set("input:touchpad:scroll_factor", newVal)
                        }
                    }
                }
            }
        }

        // Keybinds
        ContentSection {
            id: keybindsSection
            icon: "keyboard"
            title: Translation.tr("Keybinds")

            property var editingBinding: null
            readonly property var overrideEntries: {
                const overrides = HyprlandKeybindOverrides.state.overrides;
                return Object.keys(overrides).sort().map(identity => ({
                    identity: identity,
                    entry: overrides[identity],
                }));
            }
            readonly property var addConflicts: {
                const flatDefault = HyprlandKeybindOverrides.flatDefaultBinds;
                const flatUser = HyprlandKeybindOverrides.flatUserBinds;
                const overrideState = HyprlandKeybindOverrides.state;
                void flatDefault; void flatUser; void overrideState;
                if (!addCapture.hasChord)
                    return [];
                return HyprlandKeybindOverrides.conflictsFor(addCapture.mods, addCapture.key, null);
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Rebind or remove existing shortcuts from the cheatsheet (Super+/) with the pencil on each row. Changes are written to a shell-owned override file; the shipped keybind config and your hypr/custom/keybinds.lua are never touched.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: HyprlandKeybindOverrides.shimStatus === "foreign"
                text: Translation.tr("The generated override file was edited by hand, so the shell refuses to change it. Delete %1 to edit shortcuts from here again.")
                    .arg(HyprlandKeybindOverrides.shimPath)
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: HyprlandKeybindOverrides.shimStatus === "invalid"
                    || HyprlandKeybindOverrides.shimStatus === "error"
                text: Translation.tr("Applying shortcut overrides failed: %1")
                    .arg(HyprlandKeybindOverrides.lastError)
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: keybindsSection.overrideEntries.length === 0
                text: Translation.tr("No customized shortcuts yet.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }

            ColumnLayout {
                visible: keybindsSection.overrideEntries.length > 0
                Layout.fillWidth: true
                spacing: Appearance.spacing.space25

                Repeater {
                    model: keybindsSection.overrideEntries
                    delegate: RowLayout {
                        id: overrideRow
                        required property var modelData
                        readonly property var chord: HyprlandKeybindOverrides.splitIdentity(modelData.identity)
                        Layout.fillWidth: true
                        Layout.leftMargin: Appearance.spacing.space100
                        Layout.rightMargin: Appearance.spacing.space100
                        spacing: Appearance.spacing.space100

                        Repeater {
                            model: [...overrideRow.chord.mods, overrideRow.chord.key]
                            delegate: KeyboardKey {
                                required property var modelData
                                key: modelData
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const entry = overrideRow.modelData.entry;
                                if (entry.action === "remove")
                                    return Translation.tr("Removed");
                                if (entry.action === "rebind")
                                    return Translation.tr("%1 → now %2")
                                        .arg(entry.description)
                                        .arg([...entry.mods, entry.key].join(" + "));
                                return Translation.tr("Runs: %1").arg(entry.command);
                            }
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSecondaryContainer
                            elide: Text.ElideRight
                        }

                        RippleButton {
                            id: overrideEditButton
                            // findBinding is an invokable, not a property: the
                            // binding cannot see the tree change through it, so
                            // reference the tree explicitly to stay reactive.
                            visible: {
                                const tree = HyprlandKeybinds.keybinds;
                                void tree;
                                return HyprlandKeybinds.findBinding(overrideRow.modelData.identity) !== null;
                            }
                            implicitWidth: 30
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            onClicked: {
                                keybindsSection.editingBinding =
                                    HyprlandKeybinds.findBinding(overrideRow.modelData.identity);
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: Appearance.font.pixelSize.larger
                                text: "edit"
                            }
                            StyledToolTip { text: Translation.tr("Edit") }
                        }

                        RippleButton {
                            id: overrideResetButton
                            enabled: HyprlandKeybindOverrides.shimStatus !== "foreign"
                            implicitWidth: 30
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            onClicked: HyprlandKeybindOverrides.reset(overrideRow.modelData.identity)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: Appearance.font.pixelSize.larger
                                text: "restart_alt"
                                color: Appearance.colors.colError
                            }
                            StyledToolTip { text: Translation.tr("Reset to default") }
                        }
                    }
                }
            }

            DialogButton {
                visible: keybindsSection.overrideEntries.length > 0
                enabled: HyprlandKeybindOverrides.shimStatus !== "foreign"
                buttonText: Translation.tr("Reset all shortcuts to defaults")
                colEnabled: Appearance.colors.colError
                onClicked: HyprlandKeybindOverrides.resetAll()
            }

            Rectangle {
                visible: keybindsSection.editingBinding !== null
                Layout.fillWidth: true
                Layout.topMargin: Appearance.spacing.space100
                implicitHeight: settingsKeybindEditor.implicitHeight + Appearance.spacing.space300 * 2
                color: Appearance.colors.colLayer1
                radius: Appearance.rounding.normal

                KeybindEditor {
                    id: settingsKeybindEditor
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: Appearance.spacing.space300
                    }
                    bindingData: keybindsSection.editingBinding
                    onDone: keybindsSection.editingBinding = null
                }
            }

            ContentSubsection {
                title: Translation.tr("Add a shortcut")

                KeybindChordCapture {
                    id: addCapture
                    Layout.fillWidth: true
                }

                ConfigTextArea {
                    id: addCommandField
                    buttonIcon: "terminal"
                    text: Translation.tr("Command")
                    description: Translation.tr("Executed when the shortcut is pressed")
                    singleLine: true
                }

                ConfigTextArea {
                    id: addDescriptionField
                    buttonIcon: "description"
                    text: Translation.tr("Label")
                    description: Translation.tr("Shown in the cheatsheet")
                    singleLine: true
                }

                Repeater {
                    model: keybindsSection.addConflicts
                    delegate: StyledText {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.submap.length > 0
                            ? Translation.tr("Conflicts with \"%1\" (submap %2)")
                                .arg(modelData.description).arg(modelData.submap)
                            : Translation.tr("Conflicts with \"%1\"").arg(modelData.description)
                        color: Appearance.colors.colError
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.Wrap
                    }
                }

                DialogButton {
                    id: addBindingButton
                    enabled: addCapture.hasChord
                        && addCommandField.value.trim().length > 0
                        && keybindsSection.addConflicts.length === 0
                        && HyprlandKeybindOverrides.shimStatus !== "foreign"
                    buttonText: Translation.tr("Add shortcut")
                    onClicked: {
                        HyprlandKeybindOverrides.addBinding(
                            addCapture.mods, addCapture.key,
                            addCommandField.value.trim(),
                            addDescriptionField.value.trim());
                        addCapture.clear();
                        addCommandField.value = "";
                        addDescriptionField.value = "";
                    }
                }
            }
        }

        // Visual & Aesthetics
        ContentSection {
            icon: "deblur"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Visual & Aesthetics")

            GroupedList {
                ConfigSpinBox {
                    icon: "rounded_corner"
                    text: Translation.tr("Window Rounding")
                    value: Config.options.hyprland.decoration.rounding
                    from: 0; to: 30; stepSize: 1
                    onValueModified: {
                        if (newValue === Config.options.hyprland.decoration.rounding) return
                        Config.options.hyprland.decoration.rounding = newValue
                        HyprlandConfig.set("decoration:rounding", newValue)
                    }
                }

                ConfigSpinBox {
                    icon: "border_outer"
                    text: Translation.tr("Border Size")
                    value: Config.options.hyprland.general.borderSize
                    from: 0; to: 10; stepSize: 1
                    onValueModified: {
                        if (newValue === Config.options.hyprland.general.borderSize) return
                        Config.options.hyprland.general.borderSize = newValue
                        HyprlandConfig.set("general:border_size", newValue)
                    }
                }

                ConfigSpinBox {
                    icon: "margin"
                    text: Translation.tr("Gaps In")
                    value: Config.options.hyprland.general.gapsIn
                    from: 0; to: 40; stepSize: 1
                    onValueModified: {
                        if (newValue === Config.options.hyprland.general.gapsIn) return
                        Config.options.hyprland.general.gapsIn = newValue
                        HyprlandConfig.set("general:gaps_in", newValue)
                    }
                }

                ConfigSpinBox {
                    icon: "open_in_full"
                    text: Translation.tr("Gaps Out")
                    value: Config.options.hyprland.general.gapsOut
                    from: 0; to: 60; stepSize: 1
                    onValueModified: {
                        if (newValue === Config.options.hyprland.general.gapsOut) return
                        Config.options.hyprland.general.gapsOut = newValue
                        HyprlandConfig.set("general:gaps_out", newValue)
                    }
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Active Opacity")
                    value: Math.round(Config.options.hyprland.decoration.activeOpacity * 100)
                    from: 10; to: 100; stepSize: 5
                    onValueModified: {
                        const newVal = newValue / 100.0
                        if (newVal === Config.options.hyprland.decoration.activeOpacity) return
                        Config.options.hyprland.decoration.activeOpacity = newVal
                        HyprlandConfig.set("decoration:active_opacity", newVal)
                    }
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Inactive Opacity")
                    value: Math.round(Config.options.hyprland.decoration.inactiveOpacity * 100)
                    from: 10; to: 100; stepSize: 5
                    onValueModified: {
                        const newVal = newValue / 100.0
                        if (newVal === Config.options.hyprland.decoration.inactiveOpacity) return
                        Config.options.hyprland.decoration.inactiveOpacity = newVal
                        HyprlandConfig.set("decoration:inactive_opacity", newVal)
                    }
                }
            }
        }

        // Blur
        ContentSection {
            icon: "blur_on"
            shape: MaterialShape.Shape.Cookie9Sided
            title: Translation.tr("Blur")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "blur_on"
                    text: Translation.tr("Blur")
                    infoText: Translation.tr("Enable kawase window background blur.")
                    checked: Config.options.hyprland.decoration.blur.enabled
                    onToggleRequested: {
                        const next = !Config.options.hyprland.decoration.blur.enabled
                        Config.options.hyprland.decoration.blur.enabled = next
                        HyprlandConfig.set("decoration:blur:enabled", next ? 1 : 0)
                    }
                }

                ConfigSpinBox {
                    icon: "blur_circular"
                    text: Translation.tr("Blur Size")
                    infoText: Translation.tr("Blur radius, in pixels. Larger values blur further but cost more to render.")
                    value: Config.options.hyprland.decoration.blur.size
                    from: 0; to: 100; stepSize: 1
                    onValueModified: {
                        if (newValue === Config.options.hyprland.decoration.blur.size) return
                        Config.options.hyprland.decoration.blur.size = newValue
                        HyprlandConfig.set("decoration:blur:size", newValue)
                    }
                }

                ConfigSpinBox {
                    icon: "layers"
                    text: Translation.tr("Blur Passes")
                    infoText: Translation.tr("How many blur passes to perform. More passes look smoother and cost more.")
                    value: Config.options.hyprland.decoration.blur.passes
                    from: 0; to: 10; stepSize: 1
                    onValueModified: {
                        if (newValue === Config.options.hyprland.decoration.blur.passes) return
                        Config.options.hyprland.decoration.blur.passes = newValue
                        HyprlandConfig.set("decoration:blur:passes", newValue)
                    }
                }

                ConfigSwitch {
                    buttonIcon: "opacity"
                    text: Translation.tr("Ignore Window Opacity")
                    infoText: Translation.tr("Blur behind a window even where the window itself is translucent.")
                    checked: Config.options.hyprland.decoration.blur.ignoreOpacity
                    onToggleRequested: {
                        const next = !Config.options.hyprland.decoration.blur.ignoreOpacity
                        Config.options.hyprland.decoration.blur.ignoreOpacity = next
                        HyprlandConfig.set("decoration:blur:ignore_opacity", next ? 1 : 0)
                    }
                }

                ConfigSwitch {
                    buttonIcon: "speed"
                    text: Translation.tr("Extra Optimizations")
                    infoText: Translation.tr("Enable further optimizations to the blur. Recommended.")
                    checked: Config.options.hyprland.decoration.blur.newOptimizations
                    onToggleRequested: {
                        const next = !Config.options.hyprland.decoration.blur.newOptimizations
                        Config.options.hyprland.decoration.blur.newOptimizations = next
                        HyprlandConfig.set("decoration:blur:new_optimizations", next ? 1 : 0)
                    }
                }

                ConfigSwitch {
                    buttonIcon: "layers_clear"
                    text: Translation.tr("X-Ray (Skip Tiled Windows)")
                    infoText: Translation.tr("Floating windows ignore tiled windows in their blur, so they blur the wallpaper instead.")
                    checked: Config.options.hyprland.decoration.blur.xray
                    onToggleRequested: {
                        const next = !Config.options.hyprland.decoration.blur.xray
                        Config.options.hyprland.decoration.blur.xray = next
                        HyprlandConfig.set("decoration:blur:xray", next ? 1 : 0)
                    }
                }

                ConfigSpinBox {
                    icon: "grain"
                    text: Translation.tr("Noise")
                    infoText: Translation.tr("How much noise to mix into the blur, which hides colour banding.")
                    value: Math.round(Config.options.hyprland.decoration.blur.noise * 100)
                    from: 0; to: 100; stepSize: 1
                    onValueModified: {
                        const newVal = newValue / 100.0
                        if (newVal === Config.options.hyprland.decoration.blur.noise) return
                        Config.options.hyprland.decoration.blur.noise = newVal
                        HyprlandConfig.set("decoration:blur:noise", newVal)
                    }
                }

                ConfigSpinBox {
                    icon: "contrast"
                    text: Translation.tr("Contrast")
                    infoText: Translation.tr("Contrast modulation for the blur. 100% leaves it unchanged.")
                    value: Math.round(Config.options.hyprland.decoration.blur.contrast * 100)
                    from: 0; to: 200; stepSize: 1
                    onValueModified: {
                        const newVal = newValue / 100.0
                        if (newVal === Config.options.hyprland.decoration.blur.contrast) return
                        Config.options.hyprland.decoration.blur.contrast = newVal
                        HyprlandConfig.set("decoration:blur:contrast", newVal)
                    }
                }

                ConfigSpinBox {
                    icon: "brightness_6"
                    text: Translation.tr("Brightness")
                    infoText: Translation.tr("Brightness modulation for the blur. 100% leaves it unchanged.")
                    value: Math.round(Config.options.hyprland.decoration.blur.brightness * 100)
                    from: 0; to: 200; stepSize: 1
                    onValueModified: {
                        const newVal = newValue / 100.0
                        if (newVal === Config.options.hyprland.decoration.blur.brightness) return
                        Config.options.hyprland.decoration.blur.brightness = newVal
                        HyprlandConfig.set("decoration:blur:brightness", newVal)
                    }
                }

                ConfigSpinBox {
                    icon: "palette"
                    text: Translation.tr("Vibrancy")
                    infoText: Translation.tr("Increase the saturation of blurred colours.")
                    value: Math.round(Config.options.hyprland.decoration.blur.vibrancy * 100)
                    from: 0; to: 100; stepSize: 1
                    onValueModified: {
                        const newVal = newValue / 100.0
                        if (newVal === Config.options.hyprland.decoration.blur.vibrancy) return
                        Config.options.hyprland.decoration.blur.vibrancy = newVal
                        HyprlandConfig.set("decoration:blur:vibrancy", newVal)
                    }
                }

                ConfigSpinBox {
                    icon: "dark_mode"
                    text: Translation.tr("Vibrancy On Dark Areas")
                    infoText: Translation.tr("How strongly vibrancy applies to dark areas.")
                    value: Math.round(Config.options.hyprland.decoration.blur.vibrancyDarkness * 100)
                    from: 0; to: 100; stepSize: 1
                    onValueModified: {
                        const newVal = newValue / 100.0
                        if (newVal === Config.options.hyprland.decoration.blur.vibrancyDarkness) return
                        Config.options.hyprland.decoration.blur.vibrancyDarkness = newVal
                        HyprlandConfig.set("decoration:blur:vibrancy_darkness", newVal)
                    }
                }

                ConfigSwitch {
                    buttonIcon: "web_asset"
                    text: Translation.tr("Blur Special Workspace")
                    infoText: Translation.tr("Blur behind the special workspace. Expensive.")
                    checked: Config.options.hyprland.decoration.blur.special
                    onToggleRequested: {
                        const next = !Config.options.hyprland.decoration.blur.special
                        Config.options.hyprland.decoration.blur.special = next
                        HyprlandConfig.set("decoration:blur:special", next ? 1 : 0)
                    }
                }

                ConfigSwitch {
                    buttonIcon: "menu"
                    text: Translation.tr("Blur Popups")
                    infoText: Translation.tr("Blur popups such as right-click menus.")
                    checked: Config.options.hyprland.decoration.blur.popups
                    onToggleRequested: {
                        const next = !Config.options.hyprland.decoration.blur.popups
                        Config.options.hyprland.decoration.blur.popups = next
                        HyprlandConfig.set("decoration:blur:popups", next ? 1 : 0)
                    }
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Popup Alpha Threshold")
                    infoText: Translation.tr("Pixels in a popup more transparent than this are not blurred.")
                    value: Math.round(Config.options.hyprland.decoration.blur.popupsIgnorealpha * 100)
                    from: 0; to: 100; stepSize: 1
                    onValueModified: {
                        const newVal = newValue / 100.0
                        if (newVal === Config.options.hyprland.decoration.blur.popupsIgnorealpha) return
                        Config.options.hyprland.decoration.blur.popupsIgnorealpha = newVal
                        HyprlandConfig.set("decoration:blur:popups_ignorealpha", newVal)
                    }
                }

                ConfigSwitch {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Blur Input Methods")
                    infoText: Translation.tr("Blur input methods, such as fcitx5.")
                    checked: Config.options.hyprland.decoration.blur.inputMethods
                    onToggleRequested: {
                        const next = !Config.options.hyprland.decoration.blur.inputMethods
                        Config.options.hyprland.decoration.blur.inputMethods = next
                        HyprlandConfig.set("decoration:blur:input_methods", next ? 1 : 0)
                    }
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Input Method Alpha Threshold")
                    infoText: Translation.tr("Pixels in an input method more transparent than this are not blurred.")
                    value: Math.round(Config.options.hyprland.decoration.blur.inputMethodsIgnorealpha * 100)
                    from: 0; to: 100; stepSize: 1
                    onValueModified: {
                        const newVal = newValue / 100.0
                        if (newVal === Config.options.hyprland.decoration.blur.inputMethodsIgnorealpha) return
                        Config.options.hyprland.decoration.blur.inputMethodsIgnorealpha = newVal
                        HyprlandConfig.set("decoration:blur:input_methods_ignorealpha", newVal)
                    }
                }
            }
        }

        // Autostart Apps
        ContentSection {
            icon: "app_registration"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("Autostart Apps")
            Layout.fillWidth: true

            AutostartApps {}
        }

        // Animations
        ContentSection {
            icon: "animation"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Animations")
            GroupedList {
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.hyprland.animations.enable
                    onToggleRequested: {
                        const next = !Config.options.hyprland.animations.enable
                        Config.options.hyprland.animations.enable = next
                        HyprlandConfig.set("animations:enabled", next ? 1 : 0)
                    }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Presets")
                    icon: "present_to_all"
                    currentValue: Config.options.hyprland.animations.animation
                    onSelected: newValue => {
                        Config.options.hyprland.animations.animation = newValue
                        saveAnimProc.command = [
                            "python3",
                            HyprlandConfig.configuratorScriptPath,
                            "--anim-preset", newValue
                        ]
                        saveAnimProc.running = true
                    }
                    options: [
                        { displayName: Translation.tr("Elastic"),   icon: "move_selection_right", value: "fast"      },
                        { displayName: Translation.tr("Normal"),    icon: "animation",            value: "normal"    },
                        { displayName: Translation.tr("Niri Like"), icon: "swap_horiz",          value: "niri"      },
                        { displayName: Translation.tr("Caelestia"), icon: "auto_awesome",         value: "caelestia" },
                    ]
                }
            }

            Process {
                id: saveAnimProc
                onRunningChanged: if (!running) reloadAnimProc.running = true
            }
            Process {
                id: reloadAnimProc
                command: ["hyprctl", "reload"]
            }
        }
    }
}
