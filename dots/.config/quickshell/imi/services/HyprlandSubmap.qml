pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Tracks Hyprland's active keybind submap via the `submap` IPC event.
 * Hyprland emits `submap>>NAME` when a submap is entered and `submap>>`
 * (empty data) when keybinds return to the default map; configs that exit
 * via `submap, global` report the literal name "global" instead, so both
 * count as inactive.
 */
Singleton {
    id: root

    // Raw submap name from the last event ("" when none is active).
    property string submapName: ""
    readonly property bool active: submapName.length > 0 && submapName !== "global"

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") {
                root.submapName = event.data;
            }
        }
    }
}
