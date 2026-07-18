import QtQuick
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets

BarWidgetSwitcher {
    id: root

    readonly property var manifest: PluginManager.manifestsMap["docker_plugin"]

    rowDefault: pluginContent
    rowMaterial: pluginContent
    colDefault: pluginContent
    colMaterial: pluginContent

    Component {
        id: pluginContent

        PluginNode {
            manifestNode: root.manifest?.barWidget ?? null
            pluginId: root.manifest?.id ?? ""
            optionDefinitions: root.manifest?.options ?? []
        }
    }
}
