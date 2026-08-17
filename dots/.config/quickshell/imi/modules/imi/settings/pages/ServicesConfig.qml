import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true
    bottomContentPadding: 15

    component IconButton : RippleButton {
        id: iRoot
        property string iconName
        property string textString
        property color textColor: Appearance.colors.colOnPrimary

        toggled: true
        implicitHeight: 36
        padding: Appearance.spacing.space200
        implicitWidth: layoutItem.implicitWidth + padding * 2
        buttonRadius: Appearance.rounding.full

        contentItem: Item {
            implicitWidth: layoutItem.implicitWidth
            implicitHeight: layoutItem.implicitHeight
            RowLayout {
                id: layoutItem
                anchors.centerIn: parent
                spacing: Appearance.spacing.space100
                MaterialSymbol {
                    text: iRoot.iconName
                    color: iRoot.textColor
                    iconSize: Appearance.font.pixelSize.normal
                    Layout.alignment: Qt.AlignVCenter
                }
                StyledText {
                    text: iRoot.textString
                    color: iRoot.textColor
                    font.pixelSize: Appearance.font.pixelSize.small
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    //This was intended to go into the results more deeply but in the end I didn't like it but I left it just in case lol
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
        spacing: Appearance.spacing.space250

        ContentSection {
            icon: "neurology"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("AI")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("System prompt")
                text: Config.options.ai.systemPrompt
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Qt.callLater(() => {
                        Config.options.ai.systemPrompt = text;
                    });
                }
            }

            ContentSubsection {
                title: Translation.tr("Custom OpenAI-compatible Providers")

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space200

                    Repeater {
                        model: Config.options.ai.customProviders ? Config.options.ai.customProviders.length : 0

                        delegate: ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Appearance.spacing.space150

                            GroupedList {
                                cohesive: true

                                ConfigSwitch {
                                    text: Config.options.ai.customProviders[index].name
                                        ? Translation.tr("Enable %1").arg(Config.options.ai.customProviders[index].name)
                                        : Translation.tr("Enable provider %1").arg(index + 1)
                                    checked: Config.options.ai.customProviders[index].enabled
                                    onToggleRequested: {
                                        // Whole-list assignment: JsonAdapter
                                        // lists only persist when replaced.
                                        let providers = [...Config.options.ai.customProviders];
                                        providers[index].enabled = !providers[index].enabled;
                                        Config.options.ai.customProviders = providers;
                                    }
                                }

                                ConfigTextArea {
                                    buttonIcon: "badge"
                                    text: Translation.tr("Name")
                                    placeholderText: Translation.tr("Provider Name (e.g. OpenRouter)")
                                    value: Config.options.ai.customProviders[index].name
                                    onValueChanged: {
                                        let providers = [...Config.options.ai.customProviders];
                                        if (providers[index].name !== value) {
                                            providers[index].name = value;
                                            Config.options.ai.customProviders = providers;
                                        }
                                    }
                                }

                                ConfigTextArea {
                                    buttonIcon: "link"
                                    text: Translation.tr("Base URL")
                                    placeholderText: Translation.tr("e.g. https://openrouter.ai/api/v1")
                                    fieldWidth: 240
                                    value: Config.options.ai.customProviders[index].baseUrl
                                    onValueChanged: {
                                        let providers = [...Config.options.ai.customProviders];
                                        if (providers[index].baseUrl !== value) {
                                            providers[index].baseUrl = value;
                                            Config.options.ai.customProviders = providers;
                                        }
                                    }
                                }

                                ConfigTextArea {
                                    buttonIcon: "key"
                                    text: Translation.tr("API Key")
                                    placeholderText: Translation.tr("Enter API key")
                                    password: true
                                    value: KeyringStorage.loaded ? (KeyringStorage.keyringData.apiKeys?.[`custom_provider_${index}`] || "") : ""
                                    onValueChanged: {
                                        let currentText = value;
                                        Qt.callLater(() => {
                                            if (KeyringStorage.loaded) {
                                                KeyringStorage.setNestedField(["apiKeys", `custom_provider_${index}`], currentText);
                                            }
                                        });
                                    }
                                }

                                RowLayout {
                                    id: providerActionsRow
                                    Layout.fillWidth: true

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    IconButton {
                                        id: removeProviderButton
                                        toggled: false
                                        textString: Translation.tr("Remove Provider")
                                        iconName: "delete"
                                        textColor: Appearance.colors.colError
                                        colRipple: Appearance.colors.colErrorActive
                                        onClicked: {
                                            const removedIndex = index;
                                            let providers = [...Config.options.ai.customProviders];
                                            providers.splice(removedIndex, 1);
                                            Config.options.ai.customProviders = providers;

                                            if (KeyringStorage.loaded) {
                                                KeyringStorage.setNestedField(["apiKeys", `custom_provider_${removedIndex}`], "");
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        id: sectionActionsRow
                        Layout.alignment: Qt.AlignRight
                        Layout.topMargin: Appearance.spacing.space150
                        spacing: Appearance.spacing.space150

                        IconButton {
                            id: addProviderButton
                            textString: Translation.tr("Add Provider")
                            iconName: "add"
                            onClicked: {
                                let providers = [...(Config.options.ai.customProviders || [])];
                                providers.push({ enabled: false, name: "New Provider", baseUrl: "" });
                                Config.options.ai.customProviders = providers;
                            }
                        }

                        IconButton {
                            id: fetchModelsButton
                            toggled: false
                            textColor: Appearance.colors.colPrimary
                            textString: Translation.tr("Fetch Models")
                            iconName: "sync"
                            onClicked: {
                                Ai.fetchCustomModels();
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Ai.customProviderFeedbackText
                    color: Appearance.colors.colSubtext
                    visible: text.length > 0
                }
            }
        }

        ContentSection {
            icon: "cell_tower"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Networking")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("User agent (for services that require it)")
                text: Config.options.networking.userAgent
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.networking.userAgent = text;
                }
            }

            ContentSubsection {
                title: Translation.tr("Phone Connect")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "mobile"
                        text: Translation.tr("Show your phone (via KDE Connect or Valent)")
                        checked: Config.options.networking.phoneConnect.enable
                        onToggleRequested: Config.options.networking.phoneConnect.enable = !Config.options.networking.phoneConnect.enable
                    }
                    ConfigSpinBox {
                        icon: "av_timer"
                        text: Translation.tr("Polling interval (s)")
                        value: Config.options.networking.phoneConnect.pollInterval / 1000
                        from: 2
                        to: 120
                        stepSize: 1
                        onValueModified: {
                            Config.options.networking.phoneConnect.pollInterval = newValue * 1000;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "music_cast"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Music Recognition")

            GroupedList {
                ConfigSpinBox {
                    icon: "timer_off"
                    text: Translation.tr("Total duration timeout (s)")
                    value: Config.options.musicRecognition.timeout
                    from: 10
                    to: 100
                    stepSize: 2
                    onValueModified: {
                        Config.options.musicRecognition.timeout = newValue;
                    }
                }
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (s)")
                    value: Config.options.musicRecognition.interval
                    from: 2
                    to: 10
                    stepSize: 1
                    onValueModified: {
                        Config.options.musicRecognition.interval = newValue;
                    }
                }
            }
        }



        ContentSection {
            icon: "search"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Search")

            GroupedList {
                ConfigSwitch {
                    text: Translation.tr("Use Levenshtein distance-based algorithm instead of fuzzy")
                    checked: Config.options.search.sloppy
                    onToggleRequested: Config.options.search.sloppy = !Config.options.search.sloppy
                }
            }

            ContentSubsection {
                title: Translation.tr("Prefixes")

                GroupedList {
                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "bolt"
                            fieldWidth: 100
                            text: Translation.tr("Action")
                            value: Config.options.search.prefix.action
                            onValueChanged: {
                                Config.options.search.prefix.action = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "content_paste"
                            fieldWidth: 100
                            text: Translation.tr("Clipboard")
                            value: Config.options.search.prefix.clipboard
                            onValueChanged: {
                                Config.options.search.prefix.clipboard = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "mood"
                            fieldWidth: 100
                            text: Translation.tr("Emojis")
                            value: Config.options.search.prefix.emojis
                            onValueChanged: {
                                Config.options.search.prefix.emojis = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "emoji_symbols"
                            fieldWidth: 100
                            text: Translation.tr("Icons")
                            value: Config.options.search.prefix.symbols
                            onValueChanged: {
                                Config.options.search.prefix.symbols = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "terminal"
                            fieldWidth: 100
                            text: Translation.tr("Shell command")
                            value: Config.options.search.prefix.shellCommand
                            onValueChanged: {
                                Config.options.search.prefix.shellCommand = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            fieldWidth: 100
                            buttonIcon: "travel_explore"
                            text: Translation.tr("Web search")
                            value: Config.options.search.prefix.webSearch
                            onValueChanged: {
                                Config.options.search.prefix.webSearch = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "apps"
                            fieldWidth: 100
                            text: Translation.tr("Apps")
                            value: Config.options.search.prefix.app
                            onValueChanged: {
                                Config.options.search.prefix.app = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "keyboard_command_key"
                            fieldWidth: 100
                            text: Translation.tr("Keybinds")
                            value: Config.options.search.prefix.keybinds
                            onValueChanged: {
                                Config.options.search.prefix.keybinds = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "folder"
                            fieldWidth: 100
                            text: Translation.tr("Files")
                            value: Config.options.search.prefix.file
                            onValueChanged: {
                                Config.options.search.prefix.file = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "calculate"
                            fieldWidth: 100
                            text: Translation.tr("Math")
                            value: Config.options.search.prefix.math
                            onValueChanged: {
                                Config.options.search.prefix.math = value;
                            }
                        }
                    }

                    // Only shown where Prism Launcher exists: the prefix does
                    // nothing without it, and a dead setting reads as a broken
                    // one. PrismLauncher.available comes from that service's
                    // own startup detection, so this row appears on machines
                    // that can use it and nowhere else.
                    ConfigRow {
                        uniform: true
                        visible: PrismLauncher.available
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "stadia_controller"
                            fieldWidth: 100
                            text: Translation.tr("Modpacks")
                            value: Config.options.search.prefix.prism
                            onValueChanged: {
                                Config.options.search.prefix.prism = value;
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }
            }
            ContentSubsection {
                title: Translation.tr("File search")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "folder_open"
                        text: Translation.tr("Enable file/folder search")
                        checked: Config.options.search.fileSearch.enable
                        onToggleRequested: Config.options.search.fileSearch.enable = !Config.options.search.fileSearch.enable
                    }
                    ConfigTextArea {
                        id: fileSearchRootField
                        Layout.fillWidth: true
                        fieldWidth: 320
                        buttonIcon: "home_storage"
                        text: Translation.tr("Search root (empty = home folder)")
                        value: Config.options.search.fileSearch.root
                        onValueChanged: {
                            fileSearchRootDebounceTimer.restart();
                        }

                        Timer {
                            id: fileSearchRootDebounceTimer
                            interval: 600
                            repeat: false
                            onTriggered: {
                                Config.options.search.fileSearch.root = fileSearchRootField.value;
                            }
                        }
                    }
                }
            }
            ContentSubsection {
                title: Translation.tr("Web search")

                GroupedList {
                    ConfigTextArea {
                        id: baseUrlField
                        Layout.fillWidth: true
                        fieldWidth: 320
                        buttonIcon: "travel_explore"
                        text: Translation.tr("Base URL")
                        value: Config.options.search.engineBaseUrl
                        onValueChanged: {
                            baseUrlDebounceTimer.restart();
                        }

                        Timer {
                            id: baseUrlDebounceTimer
                            interval: 600
                            repeat: false
                            onTriggered: {
                                Config.options.search.engineBaseUrl = baseUrlField.value;
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "deployed_code_update"
            title: Translation.tr("System updates (Arch only)")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "update"
                    text: Translation.tr("Enable update checks")
                    checked: Config.options.updates.enableCheck
                    onToggleRequested: Config.options.updates.enableCheck = !Config.options.updates.enableCheck
                }

                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Check interval (mins)")
                    value: Config.options.updates.checkInterval
                    from: 60
                    to: 1440
                    stepSize: 60
                    onValueModified: {
                        Config.options.updates.checkInterval = newValue;
                    }
                }
            }
        }

        ContentSection {
            // Only for users who chose to install Clight; everyone else never
            // sees this section (the daemon-detection gate from the proposal).
            visible: Clight.installed
            icon: "brightness_auto"
            title: Translation.tr("Clight")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "handshake"
                    text: Translation.tr("Cooperate with the Clight daemon")
                    checked: Config.options.light.clight.enable
                    onToggleRequested: Config.options.light.clight.enable = !Config.options.light.clight.enable
                }
                ConfigSwitch {
                    visible: Clight.available
                    buttonIcon: "brightness_auto"
                    text: Translation.tr("Automatic brightness calibration")
                    checked: Clight.autoCalibration
                    onToggleRequested: Clight.setAutoCalibration(!Clight.autoCalibration)
                }
                ConfigSpinBox {
                    visible: Clight.available
                    icon: "light_mode"
                    text: Translation.tr("Day temperature (K)")
                    value: Clight.dayTemperature
                    from: 1000
                    to: 10000
                    stepSize: 100
                    onValueModified: {
                        Clight.setDayTemperature(newValue);
                    }
                }
                ConfigSpinBox {
                    visible: Clight.available
                    icon: "bedtime"
                    text: Translation.tr("Night temperature (K)")
                    value: Clight.nightTemperature
                    from: 1000
                    to: 10000
                    stepSize: 100
                    onValueModified: {
                        Clight.setNightTemperature(newValue);
                    }
                }
            }
            StyledText {
                visible: Clight.available && Clight.sensorAvailable
                color: Appearance.colors.colSubtext
                text: Translation.tr("Ambient brightness: %1%").arg(Math.round(Clight.ambientBrightness * 100))
            }
            StyledText {
                visible: Config.options.light.clight.enable && !Clight.available
                color: Appearance.colors.colSubtext
                text: Translation.tr("Clight is installed but not running.")
            }
            StyledText {
                visible: Clight.available && Hyprsunset.temperatureActive
                color: Appearance.colors.colSubtext
                text: Translation.tr("Night light is also on — it and Clight may fight over screen temperature.")
            }
        }

        ContentSection {
            icon: "weather_mix"
            shape: MaterialShape.Shape.Pill
            title: Translation.tr("Weather")
            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Provider")
                    icon: "cloud"
                    currentValue: Config.options.bar.weather.provider
                    onSelected: newValue => { Config.options.bar.weather.provider = newValue; }
                    options: [
                        { displayName: Translation.tr("OpenWeatherMap"), icon: "key",      value: "owm" },
                        { displayName: Translation.tr("wttr.in"),        icon: "public",   value: "wttr" }
                    ]
                }
                ConfigTextArea {
                    id: weatherApiKeyField
                    Layout.fillWidth: true
                    // A GroupedList row declares its visibility this way or it
                    // leaves an empty plate behind - see GroupedList.qml.
                    property bool rowVisible: Config.options.bar.weather.provider === "owm"
                    fieldWidth: 250
                    buttonIcon: "vpn_key"
                    text: Translation.tr("OpenWeatherMap API key (leave empty for the built-in key)")
                    value: Config.options.bar.weather.apiKey
                    onValueChanged: weatherApiKeyDebounceTimer.restart()

                    Timer {
                        id: weatherApiKeyDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: Config.options.bar.weather.apiKey = weatherApiKeyField.value
                    }
                }
                ConfigSwitch {
                    buttonIcon: "assistant_navigation"
                    text: Translation.tr("Enable GPS based location")
                    checked: Config.options.bar.weather.enableGPS
                    onToggleRequested: Config.options.bar.weather.enableGPS = !Config.options.bar.weather.enableGPS
                }
                ConfigSwitch {
                    buttonIcon: "thermometer"
                    text: Translation.tr("Fahrenheit unit")
                    checked: Config.options.bar.weather.useUSCS
                    onToggleRequested: Config.options.bar.weather.useUSCS = !Config.options.bar.weather.useUSCS
                }
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (m)")
                    value: Config.options.bar.weather.fetchInterval
                    from: 5
                    to: 50
                    stepSize: 5
                    onValueModified: {
                        Config.options.bar.weather.fetchInterval = newValue;
                    }
                }
                ConfigTextArea {
                    id: cityField
                    Layout.fillWidth: true
                    buttonIcon: "location_city"
                    text: Translation.tr("City name")
                    value: Config.options.bar.weather.city
                    onValueChanged: cityDebounceTimer.restart()

                    Timer {
                        id: cityDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: Config.options.bar.weather.city = cityField.value
                    }
                }
            }
        }
        WorldMap {
            Layout.fillWidth: true
            Layout.preferredHeight: 300
        }
    }
}
