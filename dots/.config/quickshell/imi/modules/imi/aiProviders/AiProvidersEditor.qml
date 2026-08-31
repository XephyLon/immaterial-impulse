import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
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
                        // Only a keystroke may write - see the header note.
                        if (!textArea.activeFocus) return;
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
                        if (!textArea.activeFocus) return;
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
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    }

                    IconButton {
                        toggled: false
                        textString: Translation.tr("Remove Provider")
                        iconName: "delete"
                        textColor: Appearance.colors.colError
                        colRipple: Appearance.colors.colErrorActive
                        onClicked: {
                            const removedIndex = index;
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
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        Layout.topMargin: Appearance.spacing.space150
        spacing: Appearance.spacing.space150

        IconButton {
            textString: Translation.tr("Add Provider")
            iconName: "add"
            onClicked: {
                let providers = [...(Config.options.ai.customProviders || [])];
                providers.push({ enabled: false, name: "New Provider", baseUrl: "" });
                Config.options.ai.customProviders = providers;
            }
        }

        IconButton {
            toggled: false
            textColor: Appearance.colors.colPrimary
            textString: Translation.tr("Fetch Models")
            iconName: "sync"
            onClicked: {
                Ai.fetchCustomModels();
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
