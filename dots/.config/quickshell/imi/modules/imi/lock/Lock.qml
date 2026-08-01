pragma ComponentBehavior: Bound
import qs
import qs.modules.common.panels.lock
import QtQuick
import Quickshell

LockScreen {
    id: root

    lockSurface: LockSurface {
        context: root.context
    }

    // Push everything down visually without mutating compositor workspace state.
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            required property ShellScreen modelData
            property bool shouldPush: GlobalStates.screenLocked
            property string targetMonitorName: modelData.name
            property int verticalMovementDistance: modelData.height
            property int horizontalSqueeze: modelData.width * 0.2
        }
    }
}
