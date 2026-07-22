import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: rootWidget
    required property var manifest
    required property string screenName

    configEntryName: manifest ? "plugin_" + manifest.id : "plugin_unknown"

    // Plugin ids and monitor names are dynamic, so their layout cannot safely live in
    // Config's fixed JsonAdapter schema. PluginState persists it as raw JSON instead.
    property var currentConfig: manifest
        ? PluginState.position(manifest.id, screenName)
        : PluginState.defaultPosition()
    placementStrategy: currentConfig.placementStrategy || "free"

    // Dragging assigns targetX/targetY directly and therefore intentionally
    // breaks their initial bindings. Re-apply persisted geometry whenever the
    // external state file changes so preset switches also move live widgets.
    function applyPersistedPosition() {
        const nextX = currentConfig.x !== undefined ? currentConfig.x : 100;
        const nextY = currentConfig.y !== undefined ? currentConfig.y : 100;
        rootWidget.targetX = Math.max(0, Math.min(nextX, scaledScreenWidth - width));
        rootWidget.targetY = Math.max(0, Math.min(nextY, scaledScreenHeight - height));
    }

    onCurrentConfigChanged: applyPersistedPosition()
    Component.onCompleted: applyPersistedPosition()

    onReleased: {
        rootWidget.targetX = rootWidget.x;
        rootWidget.targetY = rootWidget.y;
        if (!manifest) return;
        PluginState.setPosition(manifest.id, screenName, {
            x: rootWidget.targetX,
            y: rootWidget.targetY,
            placementStrategy: rootWidget.placementStrategy
        });
    }

    width: Math.max(manifest ? (manifest.defaultWidth || 0) : 0, pluginNode.width)
    height: Math.max(manifest ? (manifest.defaultHeight || 0) : 0, pluginNode.height)

    PluginNode {
        id: pluginNode
        z: 1
        // Render package widgets on a bounded texture. This avoids the background
        // layer swallowing package content on some Wayland scene-graph paths
        // while keeping the texture widget-sized.
        layer.enabled: width > 0 && height > 0
        layer.smooth: true
        manifestNode: rootWidget.manifest ? rootWidget.manifest.desktopWidget : null
        pluginId: rootWidget.manifest?.id ?? ""
        optionDefinitions: rootWidget.manifest?.options ?? []
        basePath: rootWidget.manifest?._basePath ?? ""
        anchors.centerIn: parent
    }

}
