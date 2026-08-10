import QtQuick
import qs.modules.common.plugins
import "../../designsystem/widgets" as Expressive

Item {
    id: root
    readonly property var blurRegions: content.blurRegions
    readonly property bool managesBlurTint: content.managesBlurTint
    // The span the host resolved, handed down by PluginNode: stored choice,
    // then the manifest default. The host owns which size this widget is; the
    // widget owns what that size looks like. It used to own both, through a
    // `sizeMode` choice option of its own - a second mechanism for the concept
    // `__gridSize` now owns, in the same format.
    property string hostGridSize: ""
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    width: implicitWidth
    height: implicitHeight
    Expressive.DesktopWeatherWidget {
        id: content
        width: implicitWidth
        height: implicitHeight
        sizeMode: root.hostGridSize || "3x1"
        useBlurBackground: PluginState.option("nandoroid_weather", "blurEnabled", false)
        backgroundOpacity: PluginState.effectiveBackgroundOpacity("nandoroid_weather")
    }
}
