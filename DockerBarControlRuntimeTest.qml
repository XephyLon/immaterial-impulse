import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.ii.bar

ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: 3840
        implicitHeight: Appearance.sizes.barHeight
        color: "transparent"

        BarContent {
            anchors.fill: parent
            suppressDockerForMemoryTest: true
        }
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: Qt.exit(0)
    }
}
