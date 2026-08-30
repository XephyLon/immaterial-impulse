import QtQuick
import qs.modules.common.plugins
import "../../designsystem/widgets" as Expressive

// The system monitor's cards, pointed at the graphics side: GPU use, VRAM,
// and swap. A separate package rather than three more cards on the original,
// because the host places ONE instance per plugin - a user who wants both
// rows needs both plugins, and one who wants only this row places only this.
// The composition is the wrapper's whole contribution (the port rule): the
// entry component's default stays the upstream CPU/RAM/disk trio, and only
// this manifest's package asks it for ["gpu", "vram", "swap"].
Item {
    // Explicit root id - without it hostResizeBow/hostDragging resolve by
    // dynamic scope up the creation chain (the lesson the system monitor's
    // own wrapper records).
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
        cards: ["gpu", "vram", "swap"]
        resizeBow: root.hostResizeBow
        dragging: root.hostDragging
        boxInMotion: root.hostBoxInMotion
        width: implicitWidth
        height: implicitHeight
        isVertical: PluginState.option("nandoroid_system_monitor_gpu", "vertical", false)
        useBlurBackground: PluginState.option("nandoroid_system_monitor_gpu", "blurEnabled", false)
        backgroundOpacity: PluginState.effectiveBackgroundOpacity("nandoroid_system_monitor_gpu")
        onVerticalRequested: value => PluginState.setOption("nandoroid_system_monitor_gpu", "vertical", value)
    }
}
