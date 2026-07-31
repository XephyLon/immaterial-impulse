import QtQuick
import Quickshell.Hyprland

Loader {
    id: root

    property string name: ""
    property string description: ""
    signal pressed()
    signal released()

    active: true

    sourceComponent: GlobalShortcut {
        name: root.name
        description: root.description
        onPressed: root.pressed()
        onReleased: root.released()
    }
}
