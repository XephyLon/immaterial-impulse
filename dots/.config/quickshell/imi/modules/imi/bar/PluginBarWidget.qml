import QtQuick
import qs.modules.common
import qs.modules.common.plugins

// Package bar entry points need a single sizing owner. Routing them through
// PluginNode added a second Loader whose width was simultaneously derived from
// and assigned by the bar layout. Some QML package roots respond to that cycle
// with perpetual relayout, causing both a zero-width widget and runaway memory.
Item {
    id: root

    property string pluginId: ""
    property bool vertical: Config.options.bar.vertical

    readonly property var manifest: PluginManager.manifestsMap[pluginId]
    readonly property var entryPoint: manifest?.barWidget ?? null
    readonly property string basePath: entryPoint?._basePath ?? manifest?._basePath ?? ""
    readonly property string componentPath: entryPoint?.component && basePath
        ? (String(entryPoint.component).startsWith("/")
            ? String(entryPoint.component)
            : basePath + "/" + String(entryPoint.component).replace(/^\.\//, ""))
        : ""

    implicitWidth: packageLoader.status === Loader.Ready
        ? Math.max(1, packageLoader.item?.implicitWidth ?? packageLoader.item?.width ?? 1)
        : 1
    implicitHeight: packageLoader.status === Loader.Ready
        ? Math.max(1, packageLoader.item?.implicitHeight ?? packageLoader.item?.height ?? 1)
        : Appearance.sizes.barHeight

    Loader {
        id: packageLoader
        source: root.componentPath
        asynchronous: true

        onLoaded: {
            if (!item) return;
            if (item.hasOwnProperty("vertical")) item.vertical = Qt.binding(() => root.vertical);
            if (item.hasOwnProperty("pluginId")) item.pluginId = root.pluginId;
        }

        onStatusChanged: {
            if (status === Loader.Error)
                console.warn(`[PluginBarWidget] Failed to load ${root.pluginId} from ${root.componentPath}`);
        }
    }
}
