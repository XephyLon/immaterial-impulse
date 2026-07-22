import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

// Shared blur backdrop for desktop widgets (plugins + the User Card). For static
// image wallpapers it self-blurs the wallpaper region behind the surface; for a
// Wallpaper Engine wallpaper it hands off to LiveWallpaperBlur so Hyprland blurs
// the animated layer directly beneath. Keep LiveWallpaperBlur a bare Rectangle
// with no offscreen layer/transform above it or the compositor samples a cached
// texture instead of the live frame.
Item {
    id: root

    property string wallpaperSource: ""
    property bool liveWallpaperActive: false
    property real cornerRadius: Appearance.rounding?.verylarge ?? 30

    // Monitor size and this surface's absolute top-left on that monitor. Used to
    // clip out the wallpaper slice that sits behind the surface. Without them the
    // still path would crop the whole wallpaper into the widget rect, showing a
    // shrunken copy of the entire wallpaper instead of the region the live
    // compositor blur reveals for Wallpaper Engine.
    property real screenWidth: 0
    property real screenHeight: 0
    property real surfaceX: 0
    property real surfaceY: 0

    // Natural wallpaper dimensions. Kept separate from the sampled image because
    // setting sourceClipRect makes an Image report the clip size as its source
    // size, which would make the clip math below circular.
    Image {
        id: wallpaperMetadata
        source: root.wallpaperSource ? ("file://" + root.wallpaperSource) : ""
        asynchronous: true
        cache: false
        visible: false
    }

    Image {
        id: wallpaperSample
        anchors.fill: parent
        source: root.wallpaperSource ? ("file://" + root.wallpaperSource) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false

        // Cover the monitor exactly as Background.qml's PreserveAspectCrop does,
        // then clip only the source pixels beneath this surface so the blur lines
        // up 1:1 with the wallpaper behind it. Bounded to the widget rect - never
        // a full-screen image per surface.
        readonly property real srcW: wallpaperMetadata.sourceSize.width
        readonly property real srcH: wallpaperMetadata.sourceSize.height
        readonly property real coverScale: (srcW > 0 && srcH > 0
                && root.screenWidth > 0 && root.screenHeight > 0)
            ? Math.max(root.screenWidth / srcW, root.screenHeight / srcH)
            : 0
        sourceClipRect: coverScale > 0
            ? Qt.rect(
                (srcW - root.screenWidth / coverScale) / 2 + root.surfaceX / coverScale,
                (srcH - root.screenHeight / coverScale) / 2 + root.surfaceY / coverScale,
                Math.max(1, root.width / coverScale),
                Math.max(1, root.height / coverScale))
            : Qt.rect(0, 0, 0, 0)
    }

    FastBlur {
        id: blurredBackground
        anchors.fill: wallpaperSample
        source: wallpaperSample
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
