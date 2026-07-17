import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins

ContentPage {
    id: root

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.implicitHeight
        clip: true

        ColumnLayout {
            id: contentCol
            width: parent.width
            spacing: 16

            ContentSection {
                title: Translation.tr("Available Plugins")
                Layout.fillWidth: true
                icon: "extension"
                shape: MaterialShape.Shape.Diamond

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Repeater {
                        model: PluginManager.availablePlugins

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: configSwitch.implicitHeight + 16
                            color: Appearance.colors.colLayer1
                            radius: Appearance.rounding.normal

                            ConfigSwitch {
                                id: configSwitch
                                anchors.fill: parent
                                anchors.margins: 8

                                required property var modelData
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
                    }
                }
            }
        }
    }
}
