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
            spacing: Appearance.spacing.unsharpen

            Repeater {
                model: PluginManager.availablePlugins

                ColumnLayout {
                    id: pluginGroup
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Appearance.spacing.unsharpen

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: configSwitch.implicitHeight + 16
                        color: Appearance.colors.colLayer1
                        radius: Appearance.rounding.normal

                        ConfigSwitch {
                            id: configSwitch
                            anchors.fill: parent
                            anchors.margins: Appearance.spacing.small

                            property var modelData: pluginGroup.modelData
                            text: modelData.name
                            description: modelData.description || ""

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
