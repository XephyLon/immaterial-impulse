import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

// Keep this structure identical to the User Card blur path. The hidden image
// and widget-sized FastBlur establish the render surface; LiveWallpaperBlur is
// anchored to that exact surface so Hyprland samples the animated layer behind
// it when liveWallpaperActive is true.
Item {
    id: root

    property string wallpaperSource: ""
    property bool liveWallpaperActive: false
    property real cornerRadius: Appearance.rounding?.verylarge ?? 30

    Image {
        id: backgroundImage
        anchors.fill: parent
        source: root.wallpaperSource ? ("file://" + root.wallpaperSource) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
    }

    FastBlur {
        id: blurredBackground
        anchors.fill: backgroundImage
        source: backgroundImage
        visible: !root.liveWallpaperActive
        radius: 48
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: root.width
                height: root.height
                radius: root.cornerRadius
            }
        }
    }

    LiveWallpaperBlur {
        anchors.fill: blurredBackground
        cornerRadius: root.cornerRadius
    }
}
