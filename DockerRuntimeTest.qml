import QtQuick
import Quickshell
import qs.modules.ii.bar

ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: 180
        implicitHeight: 80
        color: "transparent"

        DockerPlugin {
            id: dockerWidget
            anchors.centerIn: parent
            useOutsideClickGrab: false
        }
    }

    Timer {
        interval: 2500
        running: true
        onTriggered: {
            dockerWidget.popupOpen = true;
        }
    }

    Timer {
        interval: 4000
        running: true
        onTriggered: {
            dockerWidget.popupOpen = false;
        }
    }

    Timer {
        interval: 3000
        running: true
        onTriggered: {
            if (!dockerWidget.popupOpen) Qt.exit(41);
        }
    }

    Timer {
        interval: 5500
        running: true
        onTriggered: {
            dockerWidget.popupOpen = true;
        }
    }

    Timer {
        interval: 7500
        running: true
        onTriggered: {
            dockerWidget.popupOpen = false;
        }
    }

    Timer {
        interval: 6500
        running: true
        onTriggered: {
            if (!dockerWidget.popupOpen) Qt.exit(42);
        }
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: Qt.exit(0)
    }
}
