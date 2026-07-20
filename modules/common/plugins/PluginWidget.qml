import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
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
    readonly property real blurTintOpacity: manifest
        ? PluginState.option(manifest.id, "blurTintOpacity", 0.1)
        : 0.1
    readonly property bool hasBlurSurface: !pluginNode.hasCustomBlurRegions
        || pluginNode.blurRegions.length > 0

    configEntryName: manifest ? "plugin_" + manifest.id : "plugin_unknown"

    // Plugin ids and monitor names are dynamic, so their layout cannot safely live in
    // Config's fixed JsonAdapter schema. PluginState persists it as raw JSON instead.
    property var currentConfig: manifest
        ? PluginState.position(manifest.id, screenName)
        : PluginState.defaultPosition()
    placementStrategy: currentConfig.placementStrategy || "free"

    // Override targetX and targetY to avoid errors when configEntry is undefined
    targetX: Math.max(0, Math.min(currentConfig.x !== undefined ? currentConfig.x : 100, scaledScreenWidth - width))
    targetY: Math.max(0, Math.min(currentConfig.y !== undefined ? currentConfig.y : 100, scaledScreenHeight - height))

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

    Item {
        id: blurredBackdrop
        z: -1
        anchors.fill: parent
        clip: true
        visible: rootWidget.blurEnabled && rootWidget.hasBlurSurface
            && Config.options.appearance.transparency.enable
        layer.enabled: visible
        layer.effect: OpacityMask {
            maskSource: Item {
                width: blurredBackdrop.width
                height: blurredBackdrop.height

                Repeater {
                    model: pluginNode.hasCustomBlurRegions
                        ? pluginNode.blurRegions
                        : [{ x: 0, y: 0, width: blurredBackdrop.width,
                            height: blurredBackdrop.height, radius: rootWidget.widgetRounding }]

                    Rectangle {
                        required property var modelData
                        x: Number(modelData.x || 0)
                        y: Number(modelData.y || 0)
                        width: Number(modelData.width || 0)
                        height: Number(modelData.height || 0)
                        radius: Number(modelData.radius ?? rootWidget.widgetRounding)
                        color: "white"
                    }
                }
            }
        }

        Image {
            id: wallpaperMetadata
            source: rootWidget.wallpaperPath ? ("file://" + rootWidget.wallpaperPath) : ""
            asynchronous: true
            cache: true
            visible: false
        }

        Image {
            id: wallpaperSample
            source: rootWidget.wallpaperPath ? ("file://" + rootWidget.wallpaperPath) : ""
            asynchronous: true
            cache: true
            anchors.fill: parent
            fillMode: Image.Stretch
            readonly property real cropScale: wallpaperMetadata.sourceSize.width > 0
                    && wallpaperMetadata.sourceSize.height > 0
                ? Math.max(rootWidget.scaledScreenWidth / wallpaperMetadata.sourceSize.width,
                    rootWidget.scaledScreenHeight / wallpaperMetadata.sourceSize.height)
                : 1
            readonly property real cropOffsetX: Math.max(0,
                (wallpaperMetadata.sourceSize.width * cropScale - rootWidget.scaledScreenWidth) / 2)
            readonly property real cropOffsetY: Math.max(0,
                (wallpaperMetadata.sourceSize.height * cropScale - rootWidget.scaledScreenHeight) / 2)
            sourceClipRect: Qt.rect(
                (rootWidget.x + cropOffsetX) / cropScale,
                (rootWidget.y + cropOffsetY) / cropScale,
                Math.max(1, width / cropScale),
                Math.max(1, height / cropScale))
            layer.enabled: true
            layer.effect: FastBlur { radius: 48 }
        }

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colScrim
            opacity: pluginNode.managesBlurTint ? 0 : rootWidget.blurTintOpacity
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
