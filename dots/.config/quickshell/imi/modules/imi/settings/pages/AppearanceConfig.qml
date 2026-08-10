import QtQuick
import QtQuick.Dialogs
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

    property string terminalBackgroundMessage: ""
    property bool terminalBackgroundApplyPending: false

    function scheduleTerminalBackgroundApply() {
        terminalBackgroundApplyPending = true
        terminalBackgroundApplyTimer.restart()
    }

    Timer {
        id: terminalBackgroundApplyTimer
        interval: 300
        onTriggered: {
            if (terminalBackgroundProcess.running) {
                restart()
                return
            }
            page.terminalBackgroundApplyPending = false
            terminalBackgroundProcess.command = [
                "python3",
                `${Directories.scriptPath}/terminal/apply_terminal_background.py`,
                "--config", Directories.shellConfigPath,
                "--reload"
            ]
            terminalBackgroundProcess.running = true
        }
    }

    Process {
        id: terminalBackgroundProcess
        stdout: StdioCollector { id: terminalBackgroundOutput }
        stderr: StdioCollector { id: terminalBackgroundError }
        onExited: (exitCode, exitStatus) => {
            page.terminalBackgroundMessage = exitCode === 0
                ? terminalBackgroundOutput.text.trim()
                : terminalBackgroundError.text.trim().split("\n").pop()
            if (page.terminalBackgroundApplyPending)
                terminalBackgroundApplyTimer.restart()
        }
    }

    FileDialog {
        id: terminalBackgroundFilePicker
        title: Translation.tr("Choose a terminal background image")
        currentFolder: Directories.pictures
        nameFilters: [
            Translation.tr("Images (*.png *.jpg *.jpeg *.webp *.svg)"),
            Translation.tr("All files (*)")
        ]
        onAccepted: {
            const selectedPath = FileUtils.trimFileProtocol(selectedFile.toString())
            if (selectedPath.length > 0)
                terminalBackgroundPathField.value = selectedPath
        }
    }


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
            title: Translation.tr("Icon pack")
            icon: "apps"

            IconPackSelector {
                Layout.fillWidth: true
            }
        }

        ContentSection {
            icon: "text_format"
            shape: MaterialShape.Shape.Arrow
            title: Translation.tr("Fonts")

            GroupedList {
                ConfigTextArea {
                    id: mainFontField
                    Layout.fillWidth: true
                    buttonIcon: "font_download"
                    text: Translation.tr("Font family name (e.g., Google Sans Flex)")
                    value: Config.options.appearance.fonts.main
                    onValueChanged: {
                        mainFontDebounceTimer.restart();
                    }

                    Timer {
                        id: mainFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.main = mainFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: numbersFontField
                    Layout.fillWidth: true
                    buttonIcon: "123"
                    text: Translation.tr("Numbers family name")
                    value: Config.options.appearance.fonts.numbers
                    onValueChanged: {
                        numbersFontDebounceTimer.restart();
                    }

                    Timer {
                        id: numbersFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.numbers = numbersFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: titleFontField
                    Layout.fillWidth: true
                    buttonIcon: "title"
                    text: Translation.tr("Title family name")
                    value: Config.options.appearance.fonts.title
                    onValueChanged: {
                        titleFontDebounceTimer.restart();
                    }

                    Timer {
                        id: titleFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.title = titleFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: monospaceFontField
                    Layout.fillWidth: true
                    buttonIcon: "space_bar"
                    text: Translation.tr("Monospace font name (e.g., JetBrains Mono NF)")
                    value: Config.options.appearance.fonts.monospace
                    onValueChanged: {
                        monospaceFontDebounceTimer.restart();
                    }

                    Timer {
                        id: monospaceFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.monospace = monospaceFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: iconNerdFontField
                    Layout.fillWidth: true
                    buttonIcon: "emoticon"
                    text: Translation.tr("Nerd Fonts Icons (e.g., JetBrains Mono NF)")
                    value: Config.options.appearance.fonts.iconNerd
                    onValueChanged: {
                        iconNerdFontDebounceTimer.restart();
                    }

                    Timer {
                        id: iconNerdFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.iconNerd = iconNerdFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: readingFontField
                    Layout.fillWidth: true
                    buttonIcon: "book_ribbon"
                    text: Translation.tr("Reading font name (e.g., Readex Pro)")
                    value: Config.options.appearance.fonts.reading
                    onValueChanged: {
                        readingFontDebounceTimer.restart();
                    }

                    Timer {
                        id: readingFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.reading = readingFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: expressiveFontField
                    Layout.fillWidth: true
                    buttonIcon: "favorite"
                    text: Translation.tr("Expressive font name (e.g., Space Grotesk)")
                    value: Config.options.appearance.fonts.expressive
                    onValueChanged: {
                        expressiveFontDebounceTimer.restart();
                    }

                    Timer {
                        id: expressiveFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.expressive = expressiveFontField.value;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "terminal"
            title: Translation.tr("Terminal")
            shape: MaterialShape.Shape.Cookie9Sided

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: Appearance.spacing.space100
                Layout.rightMargin: Appearance.spacing.space100
                text: Translation.tr("Note: the background pattern works with the Kitty terminal only.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
            }

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "texture"
                    text: Translation.tr("Background pattern")
                    description: Translation.tr("Show an image behind Kitty terminal content")
                    checked: Config.options.appearance.terminal.background.enabled
                    onToggleRequested: {
                        Config.options.appearance.terminal.background.enabled = !Config.options.appearance.terminal.background.enabled
                        page.scheduleTerminalBackgroundApply()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    enabled: Config.options.appearance.terminal.background.enabled
                    spacing: Appearance.spacing.space100

                    ConfigTextArea {
                        id: terminalBackgroundPathField
                        Layout.fillWidth: true
                        buttonIcon: "image"
                        text: Translation.tr("Pattern image")
                        description: Translation.tr("Absolute path to a PNG, JPEG, WebP, or SVG image")
                        placeholderText: Translation.tr("/home/user/Pictures/pattern.png")
                        value: Config.options.appearance.terminal.background.imagePath
                        fieldWidth: 260
                        singleLine: true
                        onValueChanged: {
                            Config.options.appearance.terminal.background.imagePath = value
                            page.scheduleTerminalBackgroundApply()
                        }
                    }

                    FloatingActionButton {
                        Layout.rightMargin: Appearance.spacing.space100
                        Layout.alignment: Qt.AlignVCenter
                        baseSize: 40
                        iconText: "folder_open"
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        colOnBackground: Appearance.colors.colOnSecondaryContainer
                        onClicked: terminalBackgroundFilePicker.open()
                    }
                }

                ConfigSelectionArray {
                    enabled: Config.options.appearance.terminal.background.enabled
                    text: Translation.tr("Pattern layout")
                    icon: "grid_view"
                    currentValue: Config.options.appearance.terminal.background.layout
                    onSelected: newValue => {
                        Config.options.appearance.terminal.background.layout = newValue
                        page.scheduleTerminalBackgroundApply()
                    }
                    options: [
                        { displayName: Translation.tr("Tiled"), icon: "grid_on", value: "tiled" },
                        { displayName: Translation.tr("Mirrored"), icon: "texture", value: "mirror-tiled" },
                        { displayName: Translation.tr("Scaled"), icon: "fit_screen", value: "scaled" },
                        { displayName: Translation.tr("Clamped"), icon: "crop_free", value: "clamped" }
                    ]
                }

                ConfigSpinBox {
                    enabled: Config.options.appearance.terminal.background.enabled
                    icon: "opacity"
                    text: Translation.tr("Pattern visibility (%)")
                    value: Config.options.appearance.terminal.background.opacity * 100
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueModified: {
                        Config.options.appearance.terminal.background.opacity = newValue / 100
                        page.scheduleTerminalBackgroundApply()
                    }
                }
            }

            StyledText {
                visible: page.terminalBackgroundMessage.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: Appearance.spacing.space100
                Layout.rightMargin: Appearance.spacing.space100
                text: page.terminalBackgroundMessage
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }

        ContentSection {
            icon: "colors"
            title: Translation.tr("Color generation")
            shape: MaterialShape.Shape.VerySunny

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "hardware"
                    text: Translation.tr("Shell & utilities")
                    checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    onToggleRequested: Config.options.appearance.wallpaperTheming.enableAppsAndShell = !Config.options.appearance.wallpaperTheming.enableAppsAndShell
                }
                ConfigSwitch {
                    buttonIcon: "tv_options_input_settings"
                    text: Translation.tr("Qt apps")
                    checked: Config.options.appearance.wallpaperTheming.enableQtApps
                    onToggleRequested: Config.options.appearance.wallpaperTheming.enableQtApps = !Config.options.appearance.wallpaperTheming.enableQtApps
                }
                ConfigSwitch {
                    buttonIcon: "terminal"
                    text: Translation.tr("Terminal")
                    checked: Config.options.appearance.wallpaperTheming.enableTerminal
                    onToggleRequested: Config.options.appearance.wallpaperTheming.enableTerminal = !Config.options.appearance.wallpaperTheming.enableTerminal
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        buttonIcon: "dark_mode"
                        text: Translation.tr("Force dark mode in terminal")
                        checked: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
                        onToggleRequested: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode = !Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
                    }
                }
                ConfigSpinBox {
                    icon: "invert_colors"
                    text: Translation.tr("Terminal: Harmony (%)")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100
                    from: 0; to: 100; stepSize: 10
                    onValueModified: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = newValue / 100 }
                }
                ConfigSpinBox {
                    icon: "gradient"
                    text: Translation.tr("Terminal: Harmonize threshold")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold
                    from: 0; to: 100; stepSize: 10
                    onValueModified: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = newValue }
                }
                ConfigSpinBox {
                    icon: "format_color_text"
                    text: Translation.tr("Terminal: Foreground boost (%)")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost * 100
                    from: 0; to: 100; stepSize: 10
                    onValueModified: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = newValue / 100 }
                }
            }
        }
    }
}
