import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../services/ai/openrouter_models.js" as OR
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
        OpenRouterModels.refresh();
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
    readonly property var filtered: OR.filterRows(OpenRouterModels.models, root.query)
    readonly property int shownCap: 60

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
                onClicked: root.closed()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
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
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                onClicked: OpenRouterModels.refresh(true)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Refresh the index") }
            }
        }

        ConfigTextArea {
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
            visible: OpenRouterModels.loading
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Fetching the index…")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        StyledText {
            visible: OpenRouterModels.error.length > 0 && !OpenRouterModels.loading
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
                        onClicked: root.importRow(modelRow.modelData)
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
                                    text: `${modelRow.modelData.provider} · ${Math.round(modelRow.modelData.contextWindow / 1000)}k · ${OR.priceLabel(modelRow.modelData.promptPrice, modelRow.modelData.completionPrice)}`
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                            // Bare glyphs, no tooltips: a StyledToolTip
                            // needs a host with `hovered` (a Text has none),
                            // so these showed unconditionally and leaked
                            // popup windows past the view's close.
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
