import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins

ContentPage {
    id: root
    forceWidth: true

    ContentSection {
        title: Translation.tr("Available Plugins")
        Layout.fillWidth: true
        icon: "extension"
        shape: MaterialShape.Shape.Diamond

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space25

            GroupedList {
                Layout.fillWidth: true

                ConfigSelectionArray {
                    Layout.fillWidth: true
                    text: Translation.tr("Plugin frost")
                    icon: "blur_on"
                    currentValue: Config.options.plugins.frostMode
                    onSelected: newValue => {
                        if (newValue !== Config.options.plugins.frostMode)
                            Config.options.plugins.frostMode = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Tint"), icon: "format_color_fill", value: "tint" },
                        { displayName: Translation.tr("Blur"), icon: "blur_on", value: "blur" }
                    ]
                }

                ConfigSlider {
                    Layout.fillWidth: true
                    text: Translation.tr("Blurred plugin opacity")
                    buttonIcon: "opacity"
                    from: 0
                    to: 1
                    usePercentTooltip: true
                    value: Config.options.plugins.blurOpacity
                    onValueChanged: {
                        const rounded = Math.round(value * 20) / 20;
                        if (rounded !== Config.options.plugins.blurOpacity)
                            Config.options.plugins.blurOpacity = rounded;
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100

                ConfigTextArea {
                    id: manifestUrl
                    Layout.fillWidth: true
                    buttonIcon: "extension"
                    text: Translation.tr("Plugin manifest URL")
                    placeholderText: Translation.tr("https://…/manifest.json")
                    fieldWidth: 300
                    singleLine: true
                }
                RippleButton {
                    implicitWidth: installLabel.implicitWidth + Appearance.spacing.space300
                    implicitHeight: 44
                    enabled: !PluginManager.installing
                    buttonRadius: Appearance.rounding.full
                    // ConfigTextArea.text is the row label; the field content is
                    // its `value` alias.
                    releaseAction: () => PluginManager.installFromManifest(manifestUrl.value.trim())
                    contentItem: StyledText {
                        id: installLabel
                        anchors.centerIn: parent
                        text: PluginManager.installing ? Translation.tr("Installing…") : Translation.tr("Install")
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: PluginManager.installMessage.length > 0
                text: PluginManager.installMessage
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            Repeater {
                model: PluginManager.availablePlugins

                // One plugin = one bordered card: the enable header and its
                // options live in a single rounded surface with a distinct
                // accent border, and a clear gap separates each plugin from the
                // next, so it is unambiguous which options belong to which plugin.
                Rectangle {
                    id: pluginCard
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.topMargin: Appearance.spacing.space100
                    implicitHeight: cardColumn.implicitHeight
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal

                    ColumnLayout {
                        id: cardColumn
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        spacing: 0

                        RowLayout {
                            id: pluginRow
                            Layout.fillWidth: true
                            Layout.margins: Appearance.spacing.space100
                            spacing: Appearance.spacing.space100

                            ConfigSwitch {
                                id: configSwitch
                                Layout.fillWidth: true

                                property var modelData: pluginCard.modelData
                                text: modelData.name
                                // Larger + heavier than the option-row labels so
                                // the plugin name reads as the card's heading.
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.DemiBold
                                description: {
                                    const summary = modelData.description || "";
                                    const creator = modelData.author || Translation.tr("Unknown creator");
                                    return summary.length > 0
                                        ? `${summary}\n${Translation.tr("By")} ${creator}`
                                        : `${Translation.tr("By")} ${creator}`;
                                }

                                property bool isEnabled: Config.options.plugins.enabled.includes(modelData.id)
                                checked: isEnabled
                                onCheckedChanged: {
                                    let newList = [];
                                    for (let i = 0; i < Config.options.plugins.enabled.length; i++) {
                                        newList.push(Config.options.plugins.enabled[i]);
                                    }
                                    if (checked && !isEnabled) {
                                        newList.push(modelData.id);
                                    } else if (!checked && isEnabled) {
                                        newList = newList.filter(id => id !== modelData.id);
                                    }
                                    Config.setNestedValue("plugins.enabled", newList);
                                }
                            }

                            // Third-party badge: installed plugins come from an
                            // external source (not shipped with the shell), so flag
                            // them so the user knows to trust the source.
                            Rectangle {
                                visible: pluginCard.modelData._origin === "installed"
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: badgeRow.implicitWidth + Appearance.spacing.space150
                                implicitHeight: badgeRow.implicitHeight + Appearance.spacing.space50
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colSecondaryContainer

                                RowLayout {
                                    id: badgeRow
                                    anchors.centerIn: parent
                                    spacing: Appearance.spacing.space25
                                    MaterialSymbol {
                                        text: "public"
                                        iconSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                    StyledText {
                                        text: Translation.tr("Third-party")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }

                                HoverHandler { id: badgeHover }
                                StyledToolTip {
                                    // Rectangle has no `hovered` property, so gate
                                    // explicitly or the tooltip stays visible.
                                    extraVisibleCondition: badgeHover.hovered
                                    text: Translation.tr("Installed from an external source — only enable plugins you trust")
                                }
                            }

                            // Only installed packages live on disk and can be removed;
                            // bundled plugins ship with the shell. Removal is gated on
                            // the plugin being disabled so a running plugin is never
                            // pulled out from under itself.
                            RippleButton {
                                id: deleteButton
                                visible: pluginCard.modelData._origin === "installed"
                                enabled: !configSwitch.isEnabled && !PluginManager.uninstalling
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2
                                onClicked: PluginManager.requestUninstall(pluginCard.modelData.id)

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: deleteButton.enabled
                                        ? Appearance.colors.colError : Appearance.colors.colSubtext
                                }

                                StyledToolTip {
                                    text: configSwitch.isEnabled
                                        ? Translation.tr("Disable the plugin before deleting")
                                        : Translation.tr("Delete plugin")
                                }
                            }
                        }

                        // Hairline divider separating the header from its options,
                        // shown only while the plugin is enabled (options visible).
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.leftMargin: Appearance.spacing.space100
                            Layout.rightMargin: Appearance.spacing.space100
                            implicitHeight: 1
                            color: Appearance.colors.colOutlineVariant
                            opacity: optionsRevealer.expanded ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }

                        Item {
                            id: optionsRevealer

                            Layout.fillWidth: true
                            Layout.leftMargin: Appearance.spacing.space100
                            Layout.rightMargin: Appearance.spacing.space100
                            Layout.bottomMargin: expanded ? Appearance.spacing.space50 : 0
                            implicitHeight: expanded ? optionsList.implicitHeight : 0
                            opacity: expanded ? 1 : 0
                            visible: expanded || implicitHeight > 0
                            enabled: expanded
                            clip: true

                            readonly property bool expanded: configSwitch.checked

                            Behavior on implicitHeight {
                                NumberAnimation {
                                    duration: optionsRevealer.expanded
                                        ? Appearance.animation.elementMoveEnter.duration
                                        : Appearance.animation.elementMoveExit.duration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: optionsRevealer.expanded
                                        ? Appearance.animation.elementMoveEnter.bezierCurve
                                        : Appearance.animation.elementMoveExit.bezierCurve
                                }
                            }

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            GroupedList {
                                id: optionsList
                                anchors.left: parent.left
                                anchors.right: parent.right
                                // Transparent so the option rows read as part of
                                // the unified card instead of nested sub-cards.
                                bgcolor: "transparent"

                                PluginOptions {
                                    manifest: pluginCard.modelData
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
