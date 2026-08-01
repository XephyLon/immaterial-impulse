import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

// In-shell blur backdrop for desktop widgets (plugins + the User Card). Samples
// the wallpaper region directly behind this surface and blurs it, so the widget
// reads as frosted glass over the wallpaper.
//
// - Static image wallpaper: load + clip the image region behind the surface.
// - Live Wallpaper Engine wallpaper: sample the in-shell WallpaperEngineSurface
//   (weSurfaceItem) at this surface's screen rect. WE is now drawn on the
//   background surface itself, so the old compositor-blur handoff no longer
//   applies - we blur the live frame ourselves.
Item {
    id: root

    property string wallpaperSource: ""
    property bool liveWallpaperActive: false
    // The live WallpaperEngineSurface item (whole-screen), sampled for the live
    // path. Null for the static path.
    property Item weSurfaceItem: null
    property real cornerRadius: Appearance.rounding?.verylarge ?? 30
    property int blurRadius: 48

    // Monitor size and this surface's absolute top-left on that monitor, used to
    // clip out exactly the wallpaper slice sitting behind the surface.
    property real screenWidth: 0
    property real screenHeight: 0
    property real surfaceX: 0
    property real surfaceY: 0

    readonly property string wallpaperUrl: root.wallpaperSource
        ? "file://" + root.wallpaperSource.split('/').map(s => encodeURIComponent(s)).join('/')
        : ""

    readonly property Rectangle _mask: Rectangle {
        width: root.width
        height: root.height
        radius: root.cornerRadius
    }

    // ---- Live Wallpaper Engine path: sample the WE surface at our screen rect.
    ShaderEffectSource {
        id: liveSample
        anchors.fill: parent
        visible: false
        live: true
        hideSource: false
        sourceItem: root.liveWallpaperActive ? root.weSurfaceItem : null
        sourceRect: root.liveWallpaperActive
            ? Qt.rect(root.surfaceX, root.surfaceY, Math.max(1, root.width), Math.max(1, root.height))
            : Qt.rect(0, 0, 0, 0)
    }

    // ---- Static image path: natural size probe + clipped cover sample.
    Image {
        id: wallpaperMetadata
        source: root.liveWallpaperActive ? "" : root.wallpaperUrl
        asynchronous: true
        cache: false
        visible: false
    }

    Image {
        id: wallpaperSample
        anchors.fill: parent
        source: root.liveWallpaperActive ? "" : root.wallpaperUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false

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
        anchors.fill: parent
        source: root.liveWallpaperActive ? liveSample : wallpaperSample
        radius: root.blurRadius
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: root._mask
        }
    }
}
