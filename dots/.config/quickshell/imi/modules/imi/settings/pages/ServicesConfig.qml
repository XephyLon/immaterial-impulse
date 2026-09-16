import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.aiProviders

ContentPage {
    id: page
    // The keyring loads on demand, and this page is a demand: its key fields
    // read "" and silently drop what is typed into them until it has loaded,
    // and nothing else loads it while a local model is selected.
    Component.onCompleted: {
        if (!KeyringStorage.loaded)
            KeyringStorage.fetchKeyringData();
    }
    forceWidth: true
    bottomContentPadding: 15

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
            page.scrollToY(pos.y)
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

            // A paragraph, not a value: the long-text row grows with it and
            // scrolls inside itself past ten lines.
            ConfigLongText {
                buttonIcon: "psychology"
                text: Translation.tr("System prompt")
                placeholderText: Translation.tr("How the assistant should behave")
                value: Config.options.ai.systemPrompt
                // Deferred, because the write feeds back into the binding that
                // set `value`: committing on the keystroke itself reassigns the
                // field's text while it is being typed into.
                onValueChanged: {
                    Qt.callLater(() => {
                        Config.options.ai.systemPrompt = value;
                    });
                }
            }

            ContentSubsection {
                title: Translation.tr("Folders the assistant may read")
                tooltip: Translation.tr("read_file and list_directory work only inside these; hidden files are never readable")

                // The folders, one plate each, from the config list.
                GroupedList {
                    visible: (Config.options.ai.tools.folders ?? []).length > 0
                    model: Config.options.ai.tools.folders
                    rowDelegate: Component {
                        RowLayout {
                            id: folderRow
                            property var modelData: null
                            spacing: Appearance.spacing.space200
                            MaterialSymbol {
                                Layout.leftMargin: Appearance.spacing.space100
                                text: "folder"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: String(folderRow.modelData ?? "")
                                elide: Text.ElideMiddle
                                color: Appearance.colors.colOnLayer1
                            }
                            IconButton {
                                Layout.rightMargin: Appearance.spacing.space100
                                buttonIcon: "delete"
                                buttonSize: 32
                                colText: Appearance.colors.colError
                                colRipple: Appearance.colors.colErrorActive
                                tooltip: Translation.tr("Remove folder")
                                onClicked: {
                                    const gone = String(folderRow.modelData ?? "");
                                    Config.options.ai.tools.folders = (Config.options.ai.tools.folders ?? []).filter(f => f !== gone);
                                }
                            }
                        }
                    }
                }

                GroupedList {
                    ConfigTextArea {
                        id: newFolderField
                        buttonIcon: "create_new_folder"
                        text: Translation.tr("Add a folder")
                        singleLine: true
                        placeholderText: "~/Documents"
                        confirmButtonVisible: value.trim().length > 0
                        confirmButtonIcon: "add"
                        onConfirmClicked: {
                            const folder = value.trim();
                            if (folder.length === 0) return;
                            const next = (Config.options.ai.tools.folders ?? []).slice();
                            if (next.indexOf(folder) === -1) next.push(folder);
                            Config.options.ai.tools.folders = next;
                            value = "";
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "content_paste"
                        text: Translation.tr("Let the assistant read the clipboard")
                        checked: Config.options.ai.tools.allowClipboard
                        onToggleRequested: Config.options.ai.tools.allowClipboard = !Config.options.ai.tools.allowClipboard
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Documents")
                tooltip: Translation.tr("Folders the assistant may search. Hidden files, key and config directories, and .noindex subtrees are never indexed.")

                // The indexed folders, one plate each; removing one forgets it.
                GroupedList {
                    visible: (Config.options.ai.documents.folders ?? []).length > 0
                    model: Config.options.ai.documents.folders
                    rowDelegate: Component {
                        RowLayout {
                            id: docFolderRow
                            property var modelData: null
                            spacing: Appearance.spacing.space200
                            MaterialSymbol {
                                Layout.leftMargin: Appearance.spacing.space100
                                text: "folder"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: String(docFolderRow.modelData ?? "")
                                elide: Text.ElideMiddle
                                color: Appearance.colors.colOnLayer1
                            }
                            IconButton {
                                Layout.rightMargin: Appearance.spacing.space100
                                buttonIcon: "delete"
                                buttonSize: 32
                                colText: Appearance.colors.colError
                                colRipple: Appearance.colors.colErrorActive
                                tooltip: Translation.tr("Remove and forget this folder")
                                onClicked: {
                                    const gone = String(docFolderRow.modelData ?? "");
                                    Config.options.ai.documents.folders = (Config.options.ai.documents.folders ?? []).filter(f => f !== gone);
                                    AiRag.forget(gone);
                                }
                            }
                        }
                    }
                }

                GroupedList {
                    ConfigTextArea {
                        id: newDocFolderField
                        buttonIcon: "create_new_folder"
                        text: Translation.tr("Add a folder")
                        singleLine: true
                        placeholderText: "~/Documents"
                        confirmButtonVisible: value.trim().length > 0
                        confirmButtonIcon: "add"
                        onConfirmClicked: {
                            const folder = value.trim();
                            if (folder.length === 0) return;
                            const next = (Config.options.ai.documents.folders ?? []).slice();
                            if (next.indexOf(folder) === -1) next.push(folder);
                            Config.options.ai.documents.folders = next;
                            value = "";
                        }
                    }
                    ConfigSelectionArray {
                        text: Translation.tr("Embeddings")
                        currentValue: Config.options.ai.documents.embedder
                        onSelected: value => { Config.options.ai.documents.embedder = value; }
                        options: [
                            { "displayName": Translation.tr("Keywords (offline)"), "value": "lexical" },
                            { "displayName": "nomic-embed-text (Ollama)", "value": "ollama:nomic-embed-text" },
                            { "displayName": "mxbai-embed-large (Ollama)", "value": "ollama:mxbai-embed-large" },
                        ]
                    }
                    ConfigSwitch {
                        buttonIcon: "attach_file"
                        text: Translation.tr("Attach matching passages to every message")
                        checked: Config.options.ai.documents.alwaysAttach
                        onToggleRequested: Config.options.ai.documents.alwaysAttach = !Config.options.ai.documents.alwaysAttach
                        StyledToolTip { text: Translation.tr("Off: the model calls search_documents when it decides to look") }
                    }
                    RowLayout {
                        spacing: Appearance.spacing.space200
                        MaterialSymbol {
                            Layout.leftMargin: Appearance.spacing.space100
                            text: "manage_search"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: AiRag.error.length > 0 ? AiRag.error
                                : AiRag.files === 0 ? Translation.tr("Nothing indexed yet")
                                : Translation.tr("%1 files, %2 passages, %3").arg(AiRag.files).arg(AiRag.chunks)
                                      .arg(AiRag.indexedWith.length > 0 ? AiRag.indexedWith : "")
                            color: AiRag.error.length > 0 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                        }
                        DialogButton {
                            Layout.rightMargin: Appearance.spacing.space100
                            enabled: AiRag.configured && !AiRag.indexing
                            buttonText: AiRag.indexing
                                ? Translation.tr("Indexing %1 / %2").arg(AiRag.progressDone).arg(AiRag.progressTotal)
                                : Translation.tr("Index now")
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            colRipple: Appearance.colors.colSecondaryContainerActive
                            colText: Appearance.colors.colOnSecondaryContainer
                            onClicked: AiRag.index()
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Dictation")
                tooltip: Translation.tr("Press the mic in the composer, or bind `qs ipc call ai dictate toggle` to a key")

                GroupedList {
                    ConfigSelectionArray {
                        text: Translation.tr("Transcriber")
                        currentValue: Config.options.ai.dictation.engine
                        onSelected: value => { Config.options.ai.dictation.engine = value; }
                        options: [
                            { "displayName": Translation.tr("On this machine"), "value": "local" },
                            { "displayName": Translation.tr("Provider (audio leaves this machine)"), "value": "provider" },
                        ]
                    }
                    ConfigSelectionArray {
                        property bool rowVisible: Config.options.ai.dictation.engine === "local"
                        text: Translation.tr("Model")
                        currentValue: Config.options.ai.dictation.model
                        onSelected: value => { Config.options.ai.dictation.model = value; }
                        options: [
                            { "displayName": "tiny", "value": "tiny" },
                            { "displayName": "base", "value": "base" },
                            { "displayName": "small", "value": "small" },
                            { "displayName": "medium", "value": "medium" },
                            { "displayName": "large-v3", "value": "large-v3" },
                        ]
                    }
                    RowLayout {
                        property bool rowVisible: Config.options.ai.dictation.engine === "local"
                        spacing: Appearance.spacing.space200
                        MaterialSymbol {
                            Layout.leftMargin: Appearance.spacing.space100
                            text: "download"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: !AiDictation.probed ? Translation.tr("Checking…")
                                : AiDictation.hint.length > 0 ? AiDictation.hint
                                : AiDictation.downloadState === "done" ? Translation.tr("Model ready")
                                : AiDictation.downloadState === "error" ? AiDictation.lastError
                                : AiDictation.fasterWhisper ? Translation.tr("faster-whisper found; the first use of a model downloads it unless you fetch it here")
                                : Translation.tr("whisper.cpp found")
                            color: AiDictation.hint.length > 0 || AiDictation.downloadState === "error" ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                        }
                        DialogButton {
                            Layout.rightMargin: Appearance.spacing.space100
                            enabled: AiDictation.fasterWhisper && AiDictation.downloadState !== "downloading"
                            buttonText: AiDictation.downloadState === "downloading" ? Translation.tr("Downloading…")
                                : Translation.tr("Download model")
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            colRipple: Appearance.colors.colSecondaryContainerActive
                            colText: Appearance.colors.colOnSecondaryContainer
                            onClicked: AiDictation.download()
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "send"
                        text: Translation.tr("Send the transcript at once")
                        checked: Config.options.ai.dictation.autoSend
                        onToggleRequested: Config.options.ai.dictation.autoSend = !Config.options.ai.dictation.autoSend
                        StyledToolTip { text: Translation.tr("Off: the transcript lands in the composer for editing") }
                    }
                    ConfigSpinBox {
                        icon: "timer"
                        text: Translation.tr("Stop listening after (seconds)")
                        value: Config.options.ai.dictation.maxSeconds
                        from: 5
                        to: 300
                        stepSize: 5
                        onValueModified: Config.options.ai.dictation.maxSeconds = newValue
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Custom OpenAI-compatible Providers")

                AiProvidersEditor {
                    Layout.fillWidth: true
                }
            }
        }

        ContentSection {
            icon: "cell_tower"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Networking")

            ConfigTextArea {
                Layout.fillWidth: true
                buttonIcon: "http"
                text: Translation.tr("User agent")
                placeholderText: Translation.tr("User agent (for services that require it)")
                singleLine: true
                value: Config.options.networking.userAgent
                onValueChanged: {
                    Config.options.networking.userAgent = value;
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
                ConfigSwitch {
                    buttonIcon: "star_shine"
                    text: Translation.tr("Offer \"Ask the assistant\" for long queries nothing else matches")
                    checked: Config.options.search.ai.fallthrough
                    onToggleRequested: Config.options.search.ai.fallthrough = !Config.options.search.ai.fallthrough
                    StyledToolTip { text: Translation.tr("Four or more words, no app, setting or action matched, and a usable model selected. Nothing is sent before Enter.") }
                }
            }

            ContentSubsection {
                title: Translation.tr("Inline answers")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "auto_awesome"
                        text: Translation.tr("Answer short questions inline, under the Ask row")
                        checked: Config.options.search.ai.inline
                        onToggleRequested: Config.options.search.ai.inline = !Config.options.search.ai.inline
                        StyledToolTip { text: Translation.tr("Under the assistant prefix, after a pause in typing, a one-sentence answer appears under the Ask row. This sends what you type to the selected model: only a local model answers unless the next switch is on. Enter carries the answer into the chat.") }
                    }
                    ConfigSwitch {
                        property bool rowVisible: Config.options.search.ai.inline
                        // Why nothing happens: a usable cloud model selected
                        // with this off is the case where the main switch
                        // does nothing, so this row says so, in its own
                        // description slot.
                        readonly property var selectedModel: Ai.models[Ai.currentModelId] ?? null
                        readonly property bool cloudModelWaiting: !!selectedModel && Ai.currentModelHasApiKey
                            && !StringUtils.isLoopbackUrl(selectedModel.endpoint ?? "") && !Config.options.search.ai.inlineWithCloud
                        buttonIcon: "cloud"
                        text: Translation.tr("Inline answers may use my cloud key")
                        description: cloudModelWaiting
                            ? Translation.tr("The selected model (%1) runs in the cloud, so nothing answers inline until this is on.").arg(selectedModel.name ?? Ai.currentModelId)
                            : (!selectedModel && Config.options.search.ai.inline
                                ? Translation.tr("No model is selected, so nothing answers inline yet.")
                                : "")
                        checked: Config.options.search.ai.inlineWithCloud
                        onToggleRequested: Config.options.search.ai.inlineWithCloud = !Config.options.search.ai.inlineWithCloud
                        StyledToolTip { text: Translation.tr("Off: only a model on this machine (a loopback endpoint) answers inline. On: the selected cloud model does, one request per pause in typing, at your key's cost.") }
                    }
                    ConfigSpinBox {
                        property bool rowVisible: Config.options.search.ai.inline
                        icon: "timer"
                        text: Translation.tr("Pause before asking (ms)")
                        value: Config.options.search.ai.inlineDelayMs
                        from: 300
                        to: 3000
                        stepSize: 100
                        onValueModified: Config.options.search.ai.inlineDelayMs = newValue
                    }
                    ConfigSpinBox {
                        property bool rowVisible: Config.options.search.ai.inline
                        icon: "short_text"
                        text: Translation.tr("Minimum words in the question")
                        value: Config.options.search.ai.inlineMinWords
                        from: 1
                        to: 10
                        stepSize: 1
                        onValueModified: Config.options.search.ai.inlineMinWords = newValue
                    }
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
                        ConfigTextArea {
                            Layout.fillWidth: true
                            fieldWidth: 100
                            buttonIcon: "star_shine"
                            text: Translation.tr("Ask the assistant")
                            value: Config.options.search.prefix.ai
                            onValueChanged: {
                                Config.options.search.prefix.ai = value;
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                    }
                    ConfigRow {
                        uniform: true
                        property bool rowVisible: PrismLauncher.available
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
            icon: "brightness_auto"
            title: Translation.tr("Clight")
            // The proposal's daemon-detection gate used to hide this whole
            // section (`visible: Clight.installed`). That kept dead controls
            // off the page and also made the integration unfindable: "Clight"
            // is in this page's static `sections:` list, so settings search
            // offered a section that did not exist and landed the reader on an
            // unrelated scroll position. The controls keep the gate per row;
            // the section stays, and states why it is empty.

            GroupedList {
                ConfigSwitch {
                    property bool rowVisible: Clight.installed
                    buttonIcon: "handshake"
                    text: Translation.tr("Cooperate with the Clight daemon")
                    checked: Config.options.light.clight.enable
                    onToggleRequested: Config.options.light.clight.enable = !Config.options.light.clight.enable
                }
                ConfigSwitch {
                    // `rowVisible`, never `visible`: a GroupedList row hidden
                    // with `visible` keeps an empty plate (GroupedList.qml).
                    property bool rowVisible: Clight.available
                    buttonIcon: "brightness_auto"
                    text: Translation.tr("Automatic brightness calibration")
                    checked: Clight.autoCalibration
                    onToggleRequested: Clight.setAutoCalibration(!Clight.autoCalibration)
                }
                ConfigSpinBox {
                    property bool rowVisible: Clight.available
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
                    property bool rowVisible: Clight.available
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
                visible: !Clight.installed
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Clight is not installed. With the clight daemon installed and running, the shell routes brightness changes through it and shows its colour-temperature changes on the OSD.")
            }
            StyledText {
                visible: Clight.installed && Config.options.light.clight.enable && !Clight.available
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
