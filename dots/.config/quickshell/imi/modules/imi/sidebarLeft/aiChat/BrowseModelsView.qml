import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../services/ai/openrouter_models.js" as OR
import "../../../../services/ai/model_curation.js" as Curation
import QtQuick
import QtQuick.Layouts

/**
 * OpenRouter browse-and-import (spec 2026-08-31): a read-only remote
 * index; a click imports ONE model into extraModels and selects it -
 * nothing auto-imports. Hosted by AiChat's view switcher.
 */
Rectangle {
    id: root
    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.large

    signal closed()

    transform: Translate { id: slideIn }
    Component.onCompleted: {
        slideIn.x = 24;
        slideAnim.start();
        if (root.openRouterMode) OpenRouterModels.refresh();
        if (!KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
    }
    NumberAnimation {
        id: slideAnim
        target: slideIn
        property: "x"
        to: 0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Easing.OutExpo
    }

    property string query: ""
    // With providers of your own, browse IS your providers; the OpenRouter
    // index (and its fetch, refresh, key) only exists while the provider
    // list is empty and importing is the sole way in.
    readonly property bool openRouterMode: (Config.options.ai.customProviders ?? []).length === 0
    // The merged list (spec 2026-08-31): every provider's fetched models
    // first - each with a surfaced toggle bound to its provider's curation
    // - then the OpenRouter index. One search across both.
    readonly property var providerRows: {
        const rows = [];
        for (const id of Ai.modelList) {
            const m = Ai.models[id];
            const idx = Curation.providerIndexOf(m?.key_id);
            if (idx < 0) continue;
            rows.push({
                kind: "provider",
                providerIndex: idx,
                rawId: m.model,
                id: m.model,
                name: m.name,
                provider: m.providerName ?? (Config.options.ai.customProviders?.[idx]?.name ?? ""),
                contextWindow: 0, promptPrice: 0, completionPrice: 0,
                vision: false, reasoning: m.thinking === true
            });
        }
        return rows;
    }
    readonly property var filtered: root.openRouterMode
        ? OR.filterRows(OpenRouterModels.models, root.query)
        : OR.filterRows(root.providerRows, root.query)
    readonly property int shownCap: 60

    function toggleSurfaced(row) {
        // The ONLY thing this view may write on a provider: its curation.
        let providers = [...Config.options.ai.customProviders];
        providers[row.providerIndex].selectedModels = Curation.withToggled(
            providers[row.providerIndex].selectedModels ?? [], row.rawId);
        Config.options.ai.customProviders = providers;
    }
    function surfaced(row) {
        return Curation.isSurfaced(
            Config.options.ai.customProviders?.[row.providerIndex]?.selectedModels, row.rawId);
    }

    function importRow(row) {
        Config.options.ai.extraModels = OR.withImported(
            Config.options.ai.extraModels ?? [], OR.importEntry(row));
        Ai.addUserModels();
        Ai.setModel(Ai.safeModelName(row.id));
        root.closed();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space150
        spacing: Appearance.spacing.space100

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.closed()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
            }
            StyledText {
                text: Translation.tr("Browse models")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            Item { Layout.fillWidth: true }
            RippleButton {
                visible: root.openRouterMode
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colRipple: Appearance.colors.colLayer2Active
                onClicked: OpenRouterModels.refresh(true)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Refresh the index") }
            }
        }

        ConfigTextArea {
            // With providers of your own, OpenRouter is just one of them and
            // its key lives in the editor; this field only earns its row when
            // the list is empty and importing is the sole way in.
            visible: (Config.options.ai.customProviders ?? []).length === 0
            Layout.fillWidth: true
            buttonIcon: "key"
            placeholderText: Translation.tr("OpenRouter API key")
            password: true
            value: KeyringStorage.loaded ? (KeyringStorage.keyringData.apiKeys?.openrouter || "") : ""
            onValueChanged: {
                // Only a keystroke may write - the provider editor's guard.
                if (!textArea.activeFocus) return;
                const currentText = value;
                Qt.callLater(() => {
                    if (KeyringStorage.loaded)
                        KeyringStorage.setNestedField(["apiKeys", "openrouter"], currentText);
                });
            }
        }

        ConfigTextArea {
            Layout.fillWidth: true
            buttonIcon: "search"
            placeholderText: Translation.tr("Search model, provider…")
            value: root.query
            onValueChanged: root.query = value
        }

        StyledText {
            visible: root.openRouterMode && OpenRouterModels.loading
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Fetching the index…")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        StyledText {
            visible: root.openRouterMode && OpenRouterModels.error.length > 0 && !OpenRouterModels.loading
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: OpenRouterModels.error
            color: Appearance.m3colors.m3error
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: rowsColumn.implicitHeight

            ColumnLayout {
                id: rowsColumn
                width: parent.width
                spacing: Appearance.spacing.space25

                Repeater {
                    model: root.filtered.slice(0, root.shownCap)
                    delegate: RippleButton {
                        id: modelRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 52
                        buttonRadius: Appearance.rounding.normal
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: modelRow.modelData.kind === "provider"
                            ? root.toggleSurfaced(modelRow.modelData)
                            : root.importRow(modelRow.modelData)
                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Appearance.spacing.space150
                            anchors.rightMargin: Appearance.spacing.space150
                            spacing: Appearance.spacing.space100
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelRow.modelData.name
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelRow.modelData.kind === "provider"
                                        ? Translation.tr("%1 · your provider · click to %2").arg(modelRow.modelData.provider)
                                              .arg(root.surfaced(modelRow.modelData) ? Translation.tr("hide") : Translation.tr("show"))
                                        : `${modelRow.modelData.provider} · ${Math.round(modelRow.modelData.contextWindow / 1000)}k · ${OR.priceLabel(modelRow.modelData.promptPrice, modelRow.modelData.completionPrice)}`
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                            // Bare glyphs, no tooltips: a StyledToolTip
                            // needs a host with `hovered` (a Text has none),
                            // so these showed unconditionally and leaked
                            // popup windows past the view's close.
                            MaterialSymbol {
                                visible: modelRow.modelData.kind === "provider"
                                text: root.surfaced(modelRow.modelData) ? "check_circle" : "radio_button_unchecked"
                                fill: root.surfaced(modelRow.modelData) ? 1 : 0
                                iconSize: Appearance.font.pixelSize.larger
                                color: root.surfaced(modelRow.modelData) ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                visible: modelRow.modelData.reasoning
                                text: "star_shine"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colPrimary
                            }
                            MaterialSymbol {
                                visible: modelRow.modelData.vision
                                text: "visibility"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.filtered.length > root.shownCap
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("%1 more - type to narrow").arg(root.filtered.length - root.shownCap)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }
}
