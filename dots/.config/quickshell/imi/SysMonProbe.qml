import QtQuick
import Quickshell
import qs.modules.common
import "modules/common/plugins/designsystem/widgets" as Expressive

ShellRoot {
    FloatingWindow {
        title: "SysMonProbe"
        implicitWidth: 480
        implicitHeight: 320
        color: "transparent"
        Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer0 }
        Expressive.DesktopSystemMonitorWidget { x: 24; y: 24 }
        Loader {
            x: 24; y: 160
            // Only the new tree knows `cards`; the old tree's probe copy
            // leaves this loader empty rather than failing the whole file.
            source: Qt.resolvedUrl("SysMonGpuRow.qml")
        }
    }
}
