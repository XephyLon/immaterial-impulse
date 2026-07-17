import QtQuick
import Quickshell
import qs.modules.common.widgets
import qs.services

Item {
    id: rootNode
    required property var manifestNode

    implicitWidth: componentLoader.item ? (componentLoader.item.implicitWidth || componentLoader.item.width) : 0
    implicitHeight: componentLoader.item ? (componentLoader.item.implicitHeight || componentLoader.item.height) : 0
    width: implicitWidth
    height: implicitHeight

    function resolveBinding(bindingString) {
        switch (bindingString) {
            case "DateTime.time": return DateTime.time;
            case "DateTime.date": return DateTime.date;
            case "DateTime.shortDate": return DateTime.shortDate;
            case "Battery.percentage": return Battery.percentage;
            case "Battery.charging": return Battery.charging;
            case "Battery.pluggedIn": return Battery.pluggedIn;
            case "Network.networkName": return Network.networkName;
            case "Network.primaryIp": return Network.primaryIp;
            case "SystemInfo.cpuUsage": return SystemInfo.cpuUsage;
            case "SystemInfo.ramUsage": return SystemInfo.ramUsage;
            case "Audio.volume": return Audio.volume;
            case "Audio.muted": return Audio.muted;
            default: return undefined;
        }
    }

    Loader {
        id: componentLoader
        anchors.fill: parent
        sourceComponent: {
            if (!manifestNode) return null;
            switch(manifestNode.type) {
                case "StyledText": return styledTextComponent;
                case "MaterialSymbol": return materialSymbolComponent;
                case "ResourceCard": return resourceCardComponent;
                case "StyledImage": return styledImageComponent;
                case "MaterialShape": return materialShapeComponent;
                case "Row": return rowComponent;
                case "Column": return columnComponent;
                case "Item": return itemComponent;
                case "Rectangle": return rectangleComponent;
                case "RippleButton": return rippleButtonComponent;
                default: return null;
            }
        }

        onLoaded: {
            if (!item) return;
            if (manifestNode.props) {
                for (let prop in manifestNode.props) {
                    let val = manifestNode.props[prop];
                    if (typeof val === "string" && val.startsWith("Appearance.colors.")) {
                        let colorName = val.substring(18);
                        item[prop] = Qt.binding(function() { return qs.modules.common.Appearance.colors[colorName]; });
                    } else if (typeof val === "string" && val.startsWith("Appearance.rounding.")) {
                        let rName = val.substring(20);
                        item[prop] = Qt.binding(function() { return qs.modules.common.Appearance.rounding[rName]; });
                    } else {
                        item[prop] = val;
                    }
                }
            }
            if (manifestNode.bindings) {
                for (let prop in manifestNode.bindings) {
                    let bindTarget = manifestNode.bindings[prop];
                    item[prop] = Qt.binding(function() {
                        return rootNode.resolveBinding(bindTarget);
                    });
                }
            }
        }
    }

    Component { id: styledTextComponent; StyledText {} }
    Component { id: materialSymbolComponent; MaterialSymbol {} }
    Component { id: resourceCardComponent; ResourceCard {} }
    Component { id: styledImageComponent; StyledImage {} }

    Component { id: materialShapeComponent; MaterialShape {
        Repeater {
            model: manifestNode.children || []
            PluginNode { manifestNode: modelData }
        }
    }}

    Component { id: rowComponent; Row {
        Repeater {
            model: manifestNode.children || []
            PluginNode { manifestNode: modelData }
        }
    }}

    Component { id: columnComponent; Column {
        Repeater {
            model: manifestNode.children || []
            PluginNode { manifestNode: modelData }
        }
    }}

    Component { id: itemComponent; Item {
        Repeater {
            model: manifestNode.children || []
            PluginNode { manifestNode: modelData }
        }
    }}

    Component { id: rectangleComponent; Rectangle {
        Repeater {
            model: manifestNode.children || []
            PluginNode { manifestNode: modelData }
        }
    }}
    
    Component { id: rippleButtonComponent; RippleButton {
        Repeater {
            model: manifestNode.children || []
            PluginNode { manifestNode: modelData }
        }
    }}
}
