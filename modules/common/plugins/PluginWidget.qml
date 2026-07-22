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
    readonly property bool blurEnabled: manifest
        ? PluginState.option(manifest.id, "blurEnabled", manifest.desktopWidget?.blur === true)
        : false
    readonly property real blurTintOpacity: Config.options.plugins.blurOpacity
    readonly property bool liveWallpaperActive: WallpaperEngine.stableConfigured
        && !GlobalStates.screenLocked
    readonly property bool hasBlurSurface: !pluginNode.hasCustomBlurRegions
        || pluginNode.blurRegions.length > 0

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

    // Widgets here share the same background-layer surface as the wallpaper itself
    // (see Background.qml's WlrLayershell.namespace), so there's no separate surface
    // behind them for the compositor to blur - Hyprland's `layerrule blur` has nothing
    // to do here. Match UserCardWidget.qml's approach instead: sample + blur the
    // wallpaper ourselves. The sample window tracks rootWidget.x/y live so it keeps
    // showing the correct region while the widget is being dragged.
    readonly property real widgetRounding: {
        const val = manifest?.desktopWidget?.props?.radius;
        if (typeof val === "string" && val.startsWith("Appearance.rounding.")) {
            return Appearance.rounding[val.substring(20)] ?? Appearance.rounding.large;
        }
        if (typeof val === "number") return val;
        return Appearance.rounding.large;
    }

    Repeater {
        model: rootWidget.blurEnabled
            && rootWidget.hasBlurSurface && Config.options.appearance.transparency.enable
            ? (pluginNode.hasCustomBlurRegions
                ? pluginNode.blurRegions
                : [{ x: 0, y: 0, width: rootWidget.width,
                    height: rootWidget.height, radius: rootWidget.widgetRounding }])
            : []

        WallpaperBlurSurface {
            required property var modelData
            z: 0
            x: Number(modelData.x || 0)
            y: Number(modelData.y || 0)
            width: Number(modelData.width || 0)
            height: Number(modelData.height || 0)
            wallpaperSource: rootWidget.wallpaperPath
            liveWallpaperActive: rootWidget.liveWallpaperActive
            cornerRadius: Number(modelData.radius ?? rootWidget.widgetRounding)
            // Absolute position on the monitor so the still path samples the
            // wallpaper region actually behind this surface.
            screenWidth: rootWidget.scaledScreenWidth
            screenHeight: rootWidget.scaledScreenHeight
            surfaceX: rootWidget.x + x
            surfaceY: rootWidget.y + y
        }
    }

    PluginNode {
        id: pluginNode
        z: 1
        // Package widgets render above the wallpaper-sampling backdrop on a bounded
        // texture. This avoids the background layer swallowing package content on
        // some Wayland scene-graph paths while keeping the texture widget-sized.
        layer.enabled: width > 0 && height > 0
        layer.smooth: true
        manifestNode: rootWidget.manifest ? rootWidget.manifest.desktopWidget : null
        pluginId: rootWidget.manifest?.id ?? ""
        optionDefinitions: rootWidget.manifest?.options ?? []
        basePath: rootWidget.manifest?._basePath ?? ""
        anchors.centerIn: parent
    }

}
