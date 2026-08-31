import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "../../../services/ai_provider_keys.js" as ProviderKeys

/**
 * The custom OpenAI-compatible providers editor, extracted from
 * ServicesConfig so the sidebar's keys view and the Services page render
 * ONE editor instead of drifting copies. It owns the whole vocabulary:
 * enable/name/URL/key per provider (keys in the keyring, never in
 * config.json), remove with the index-shift key migration, add, fetch.
 *
 * Name and URL write only under the user's focus: valueChanged fires for
 * a binding re-evaluation as readily as a keystroke, and a write from a
 * page-load moment is how a provider got blanked without anyone typing.
 */
ColumnLayout {
    id: root
    spacing: Appearance.spacing.space200

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
        // The press tones follow each state's own fill family: the filled
        // pill ripples in its container's Active, and the flat variant -
        // whose colLayer1 default reads as no background at all on this
        // page - ripples in the Layer2 family it hovers in.
        // A filled surface ripples in its ON-color, faint: this palette's
        // PrimaryActive sits nearly on Primary itself, which was the
        // weakness - and SecondaryContainerActive was the wrong family
        // for a colPrimary fill entirely.
        colRippleToggled: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.75)
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

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

    Repeater {
        model: Config.options.ai.customProviders ? Config.options.ai.customProviders.length : 0

        delegate: Rectangle {
            id: providerCard
            required property int index
            Layout.fillWidth: true
            // A planted card ARRIVES - fade and a small rise - instead of
            // popping into the column.
            opacity: 1
            transform: Translate { id: cardRise }
            Component.onCompleted: {
                opacity = 0;
                cardRise.y = 8;
                cardEntrance.start();
            }
            ParallelAnimation {
                id: cardEntrance
                NumberAnimation { target: providerCard; property: "opacity"; to: 1; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.OutCubic }
                NumberAnimation { target: cardRise; property: "y"; to: 0; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.OutExpo }
            }
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
            implicitHeight: cardColumn.implicitHeight + Appearance.spacing.space200 * 2

            ColumnLayout {
                id: cardColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Appearance.spacing.space200
                spacing: Appearance.spacing.space100

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space100

                    MaterialSymbol {
                        text: "cloud"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colPrimary
                    }
    StyledText {
                        elide: Text.ElideRight
                        text: Config.options.ai.customProviders[providerCard.index].name
                            || Translation.tr("Provider %1").arg(providerCard.index + 1)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: ({
                            "anthropic": "Anthropic",
                            "gemini": "Google Gemini",
                            "mistral": "Mistral",
                        })[Config.options.ai.customProviders[providerCard.index].type ?? "openai"]
                            ?? Translation.tr("OpenAI-compatible")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledSwitch {
                        // Non-checkable: the click is an INTENT and the write
                        // below is what flips the picture - a Switch moving
                        // its own `checked` destroys this binding (see
                        // lint_config_switch_intent.py's history).
                        checkable: false
                        checked: Config.options.ai.customProviders[providerCard.index].enabled === true
                        onClicked: {
                            // Whole-list assignment: JsonAdapter lists only
                            // persist when replaced.
                            let providers = [...Config.options.ai.customProviders];
                            providers[providerCard.index].enabled = !providers[providerCard.index].enabled;
                            Config.options.ai.customProviders = providers;
                        }
                    }
                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colErrorActive
                        onClicked: {
                            const removedIndex = providerCard.index;
                            const count = Config.options.ai.customProviders.length;
                            let providers = [...Config.options.ai.customProviders];
                            providers.splice(removedIndex, 1);
                            Config.options.ai.customProviders = providers;

                            // Keys are stored by list index, so every provider
                            // below the removed one moves up a slot and its key
                            // has to move with it - blanking the removed slot
                            // alone left the next provider reading its
                            // neighbour's key. See ai_provider_keys.js.
                            if (KeyringStorage.loaded) {
                                const before = KeyringStorage.keyringData.apiKeys ?? {};
                                const after = ProviderKeys.apiKeysAfterRemoval(before, removedIndex, count);
                                for (const id of ProviderKeys.changedIds(before, after))
                                    KeyringStorage.setNestedField(["apiKeys", id], after[id]);
                            }
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "delete"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colError
                        }
                        StyledToolTip { text: Translation.tr("Remove provider") }
                    }
                }

                ConfigTextArea {
                    buttonIcon: "badge"
                    text: Translation.tr("Name")
                    placeholderText: Translation.tr("Provider Name (e.g. OpenRouter)")
                    value: Config.options.ai.customProviders[providerCard.index].name
                    onValueChanged: {
                        // Only a keystroke may write - see the header note.
                        if (!textArea.activeFocus) return;
                        // Teardown ghosts: a field being destroyed with focus
                        // still on it emits one last valueChanged("") - the
                        // signature of every provider wipe so far (only the
                        // fields the user had focused came back blank). A
                        // dying view must not write, and an empty value never
                        // overwrites a real one - clearing a name is done by
                        // typing its replacement.
                        if (!root.visible) return;
                        let providers = [...Config.options.ai.customProviders];
                        if (value === "" && providers[providerCard.index].name) return;
                        if (providers[providerCard.index].name !== value) {
                            providers[providerCard.index].name = value;
                            Config.options.ai.customProviders = providers;
                        }
                    }
                }

                ConfigTextArea {
                    // Vendor types carry fixed endpoints; only the
                    // OpenAI-compatible card asks where the server is.
                    visible: (Config.options.ai.customProviders[providerCard.index].type ?? "openai") === "openai"
                    buttonIcon: "link"
                    text: Translation.tr("Base URL")
                    placeholderText: Translation.tr("e.g. https://openrouter.ai/api/v1")
                    fieldWidth: 240
                    value: Config.options.ai.customProviders[providerCard.index].baseUrl
                    onValueChanged: {
                        if (!textArea.activeFocus) return;
                        if (!root.visible) return; // teardown ghost - see Name
                        let providers = [...Config.options.ai.customProviders];
                        if (value === "" && providers[providerCard.index].baseUrl) return;
                        if (providers[providerCard.index].baseUrl !== value) {
                            providers[providerCard.index].baseUrl = value;
                            Config.options.ai.customProviders = providers;
                        }
                    }
                }

                ConfigTextArea {
                    buttonIcon: "key"
                    text: Translation.tr("API Key")
                    placeholderText: Translation.tr("Enter API key")
                    password: true
                    value: KeyringStorage.loaded ? (KeyringStorage.keyringData.apiKeys?.[`custom_provider_${providerCard.index}`] || "") : ""
                    onValueChanged: {
                        // This write was never focus-guarded at all - the
                        // same teardown ghost could blank a keyring entry.
                        if (!textArea.activeFocus) return;
                        if (!root.visible) return;
                        let currentText = value;
                        Qt.callLater(() => {
                            if (KeyringStorage.loaded) {
                                KeyringStorage.setNestedField(["apiKeys", `custom_provider_${providerCard.index}`], currentText);
                            }
                        });
                    }
                }
            }
        }
    }

    Item {
        // The empty slot: one click opens the type choice - the average
        // user never touches the config file, so ANY provider kind must be
        // addable from here. Picking plants a pre-filled card; Anthropic
        // arrives with its fixed endpoint and needs only a key.
        id: addSlot
        property bool choosing: false
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.spacing.space100
        Layout.rightMargin: Appearance.spacing.space100
        Layout.topMargin: Appearance.spacing.space100
        implicitHeight: choosing ? chooserColumn.implicitHeight + 16 : 44
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        clip: true

        function plant(type, name, baseUrl) {
            let providers = [...(Config.options.ai.customProviders || [])];
            providers.push({ "enabled": false, "name": name, "type": type,
                             "baseUrl": baseUrl, "selectedModels": [] });
            Config.options.ai.customProviders = providers;
            addSlot.choosing = false;
        }

        Canvas {
            id: dashedBorder
            anchors.fill: parent
            property color stroke: Appearance.colors.colOutline
            onStrokeChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = String(stroke);
                ctx.lineWidth = 1.5;
                ctx.setLineDash([6, 6]);
                const r = Appearance.rounding.normal;
                const inset = 2;
                ctx.beginPath();
                ctx.roundedRect(inset, inset, width - inset * 2, height - inset * 2, r, r);
                ctx.stroke();
            }
        }

        RippleButton {
            anchors.fill: parent
            opacity: addSlot.choosing ? 0 : 1
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            buttonRadius: Appearance.rounding.normal
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: addSlot.choosing = true
            contentItem: Item {
                implicitHeight: addRow.implicitHeight
                RowLayout {
                    id: addRow
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space100
                    MaterialSymbol {
                        text: "add"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: Translation.tr("Add Provider")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }

        ColumnLayout {
            id: chooserColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            opacity: addSlot.choosing ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            transform: Translate {
                y: addSlot.choosing ? 0 : -8
                Behavior on y {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
            }
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Appearance.spacing.space100
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Provider type")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: addSlot.choosing = false
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            component TypeChoice: RippleButton {
                property string label
                property string detail
                property string glyph
                Layout.fillWidth: true
                implicitHeight: 40
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                contentItem: Item {
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.spacing.space100
                        anchors.rightMargin: Appearance.spacing.space100
                        spacing: Appearance.spacing.space100
                        MaterialSymbol {
                            text: glyph
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: label
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignRight
                            text: detail
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }

            TypeChoice {
                label: Translation.tr("OpenAI-compatible")
                detail: Translation.tr("any server with /v1")
                glyph: "cloud"
                onClicked: addSlot.plant("openai", "New Provider", "")
            }
            TypeChoice {
                label: "Anthropic"
                detail: "api.anthropic.com"
                glyph: "psychology_alt"
                onClicked: addSlot.plant("anthropic", "Anthropic", "https://api.anthropic.com/v1")
            }
            TypeChoice {
                label: "Google Gemini"
                detail: "generativelanguage.googleapis.com"
                glyph: "auto_awesome"
                onClicked: addSlot.plant("gemini", "Gemini", "https://generativelanguage.googleapis.com/v1beta")
            }
            TypeChoice {
                label: "Mistral"
                detail: "api.mistral.ai"
                glyph: "air"
                onClicked: addSlot.plant("mistral", "Mistral", "https://api.mistral.ai/v1")
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
