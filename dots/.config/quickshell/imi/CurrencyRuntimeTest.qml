import QtQuick
import Quickshell

ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: 360
        implicitHeight: 180
        color: "transparent"

        Loader {
            anchors.centerIn: parent
            source: Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-currency/Widget.qml")
        }
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: Qt.exit(0)
    }
}
