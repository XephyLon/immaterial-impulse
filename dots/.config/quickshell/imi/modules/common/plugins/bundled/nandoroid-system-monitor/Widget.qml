import QtQuick
import qs.modules.common.plugins
import qs.services
import "../../designsystem/widgets" as Expressive
import "ThirdCard.js" as ThirdCard

Item {
    // Without this the file's own `root.hostResizeBow` / `root.hostDragging`
    // resolve by DYNAMIC SCOPE up the creation chain, where neither property
    // exists - so both read undefined, the three cards never lift on a drag
    // and never bow on a resize, and nothing warns. It is the only one of the
    // thirteen bundled wrappers that was missing it.
    id: root
    property point hostResizeBow: Qt.point(0, 0)
    // Set by the host while this widget is being dragged; the cards lift.
    property bool hostDragging: false
    // Set by the host while its own box is animating; the cards drop their
    // shadow for the duration rather than re-blurring into a resizing FBO.
    property bool hostBoxInMotion: false
    readonly property var blurRegions: content.blurRegions
    readonly property bool managesBlurTint: content.managesBlurTint
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    width: implicitWidth
    height: implicitHeight
    Expressive.DesktopSystemMonitorWidget {
        id: content
        resizeBow: root.hostResizeBow
        dragging: root.hostDragging
        boxInMotion: root.hostBoxInMotion
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
