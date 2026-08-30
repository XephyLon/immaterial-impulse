import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.imi.sidebarRight.quickToggles

ShellRoot {
    FloatingWindow {
        implicitWidth: 560
        implicitHeight: 160
        color: "transparent"
        Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer1 }
        ClassicQuickPanel { anchors.centerIn: parent }
    }
}
