import QtQuick
import qs.modules.common

// The translucent carrier used by Hyprland to blur the animated layer directly
// beneath the Quickshell background surface. Keep this as a plain Rectangle:
// adding an offscreen layer, shader, image, or transform makes the compositor
// sample a cached texture instead of the live Wallpaper Engine frame.
Rectangle {
    property real cornerRadius: Appearance.rounding?.verylarge ?? 30

    radius: cornerRadius
    color: Appearance.colors.colScrim
    opacity: 0.1
}
