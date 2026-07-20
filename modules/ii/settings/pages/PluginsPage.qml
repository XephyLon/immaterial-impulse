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

                ColumnLayout {
                    id: pluginGroup
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space25

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: pluginRow.implicitHeight + 16
                        color: Appearance.colors.colLayer1
                        radius: Appearance.rounding.normal

                        RowLayout {
                            id: pluginRow
                            anchors.fill: parent
                            anchors.margins: Appearance.spacing.space100
                            spacing: Appearance.spacing.space100

                            ConfigSwitch {
                                id: configSwitch
                                Layout.fillWidth: true

                                property var modelData: pluginGroup.modelData
                                text: modelData.name
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

                            // Only installed packages live on disk and can be removed;
                            // bundled plugins ship with the shell. Removal is gated on
                            // the plugin being disabled so a running plugin is never
                            // pulled out from under itself.
                            RippleButton {
                                id: deleteButton
                                visible: pluginGroup.modelData._origin === "installed"
                                enabled: !configSwitch.isEnabled && !PluginManager.uninstalling
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2
                                onClicked: PluginManager.requestUninstall(pluginGroup.modelData.id)

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
                    }

                    Item {
                        id: optionsRevealer

                        Layout.fillWidth: true
                        Layout.leftMargin: Appearance.rounding.verysmall
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

                            PluginOptions {
                                manifest: pluginGroup.modelData
                            }
                        }
                    }
                }
            }
        }
    }
}
