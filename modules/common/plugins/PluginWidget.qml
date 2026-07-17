import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: rootWidget
    required property var manifest

    configEntryName: "plugin_" + manifest.id

    // AbstractBackgroundWidget binds configEntry to Config.options.background.widgets[configEntryName]
    // If it's undefined, we provide a fallback for x, y
    property var currentConfig: Config.options.background.widgets[configEntryName] || { placementStrategy: "free", x: 100, y: 100 }
    placementStrategy: currentConfig.placementStrategy || "free"
    
    // Override targetX and targetY to avoid errors when configEntry is undefined
    targetX: Math.max(0, Math.min(currentConfig.x !== undefined ? currentConfig.x : 100, scaledScreenWidth - width))
    targetY: Math.max(0, Math.min(currentConfig.y !== undefined ? currentConfig.y : 100, scaledScreenHeight - height))

    onReleased: {
        rootWidget.targetX = rootWidget.x;
        rootWidget.targetY = rootWidget.y;
        Config.setNestedValue("background.widgets." + configEntryName + ".x", rootWidget.targetX);
        Config.setNestedValue("background.widgets." + configEntryName + ".y", rootWidget.targetY);
        Config.setNestedValue("background.widgets." + configEntryName + ".placementStrategy", placementStrategy);
    }

    width: Math.max(manifest.defaultWidth || 0, pluginNode.width)
    height: Math.max(manifest.defaultHeight || 0, pluginNode.height)

    PluginNode {
        id: pluginNode
        manifestNode: rootWidget.manifest ? rootWidget.manifest.desktopWidget : null
        anchors.centerIn: parent
    }
}
