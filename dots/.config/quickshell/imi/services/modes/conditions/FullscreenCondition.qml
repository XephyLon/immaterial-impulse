import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import ".."

/**
 * The focused monitor shows a fullscreen window (HyprlandData's polled
 * answer, the one the bar and the corners use).
 */
ModeCondition {
    id: root
    satisfied: HyprlandData.focusedMonitorHasFullscreen
    reason: root.satisfied ? (ToplevelManager.activeToplevel?.appId ?? "fullscreen") : ""
}
