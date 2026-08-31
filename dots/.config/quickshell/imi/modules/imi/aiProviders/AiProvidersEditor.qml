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
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Config.options.ai.customProviders[providerCard.index].name
                            || Translation.tr("Provider %1").arg(providerCard.index + 1)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
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

    RippleButton {
        // Add, as the M3 "empty slot" affordance: full width, dashed
        // outline, where the next card will appear.
        id: addProviderButton
        Layout.fillWidth: true
        // Inset from the window edges - full-bleed clipped the dashes.
        Layout.leftMargin: Appearance.spacing.space100
        Layout.rightMargin: Appearance.spacing.space100
        Layout.topMargin: Appearance.spacing.space100
        implicitHeight: 44
        buttonRadius: Appearance.rounding.normal
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        onClicked: {
            let providers = [...(Config.options.ai.customProviders || [])];
            providers.push({ enabled: false, name: "New Provider", baseUrl: "", selectedModels: [] });
            Config.options.ai.customProviders = providers;
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
                const inset = 2; // full stroke width inside the canvas
                ctx.beginPath();
                ctx.roundedRect(inset, inset, width - inset * 2, height - inset * 2, r, r);
                ctx.stroke();
            }
        }

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

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: Ai.customProviderFeedbackText
        color: Appearance.colors.colSubtext
        visible: text.length > 0
    }
}
