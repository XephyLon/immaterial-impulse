import QtQuick
import qs.modules.common.plugins
import qs.services
import "../../designsystem/widgets" as Expressive
import "ThirdCard.js" as ThirdCard

Item {
    property point hostResizeBow: Qt.point(0, 0)
    readonly property var blurRegions: content.blurRegions
    readonly property bool managesBlurTint: content.managesBlurTint
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    width: implicitWidth
    height: implicitHeight
    Expressive.DesktopSystemMonitorWidget {
        id: content
        resizeBow: root.hostResizeBow
        width: implicitWidth
        height: implicitHeight
        isVertical: PluginState.option("nandoroid_system_monitor", "vertical", false)
        showBattery: ThirdCard.showsBattery(
            PluginState.option("nandoroid_system_monitor", "showBattery", true),
            Battery.available)
        useBlurBackground: PluginState.option("nandoroid_system_monitor", "blurEnabled", false)
        backgroundOpacity: PluginState.effectiveBackgroundOpacity("nandoroid_system_monitor")
        onVerticalRequested: value => PluginState.setOption("nandoroid_system_monitor", "vertical", value)
    }
}
