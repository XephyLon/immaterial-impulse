import QtQuick
import qs.modules.common
import qs.modules.common.plugins
import "../../designsystem/widgets" as Expressive

Item {
    readonly property var blurRegions: content.blurRegions
    readonly property bool managesBlurTint: content.managesBlurTint
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    width: implicitWidth
    height: implicitHeight
    Expressive.DesktopSystemMonitorWidget {
        id: content
        width: implicitWidth
        height: implicitHeight
        isVertical: PluginState.option("nandoroid_system_monitor", "vertical", false)
        useBlurBackground: PluginState.option("nandoroid_system_monitor", "blurEnabled", false)
        backgroundOpacity: Config.options.plugins.blurOpacity
        onVerticalRequested: value => PluginState.setOption("nandoroid_system_monitor", "vertical", value)
    }
}
