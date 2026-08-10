import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

// In-shell blur backdrop for desktop widgets (plugins + the User Card). Samples
// the wallpaper region directly behind this surface and blurs it, so the widget
// reads as frosted glass over the wallpaper.
//
// Both wallpaper paths are one shape: a whole-screen item, sampled at this
// surface's screen rect through a ShaderEffectSource.
//
// - Live Wallpaper Engine wallpaper: the in-shell WallpaperEngineSurface
//   (weSurfaceItem). WE is now drawn on the background surface itself, so the
//   old compositor-blur handoff no longer applies - we blur the live frame
//   ourselves.
// - Static image wallpaper: a screen-sized Image of the wallpaper, cover-fitted
//   exactly as the desktop draws it (see wallpaperImage).
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
    // sample exactly the wallpaper slice sitting behind the surface.
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

    // ---- Static image path: the whole wallpaper, laid out exactly as the
    // desktop draws it, so the slice behind this surface is just a sub-rect.
    //
    // Asking for the plain file - no sourceSize, no sourceClipRect, cache on -
    // is the fix for #147, not an oversight. Those are the request parameters a
    // QQuickPixmap cache key is built from, so the per-surface clip rect this
    // used to carry gave every surface a key of its own, and `cache: false`
    // stopped even identical requests from being shared: eight widgets meant
    // sixteen full-resolution decodes of one file queued on Qt's single
    // pixmap-reader thread, and the frost came back one widget at a time, ~0.6s
    // apart. Sharing the key means every surface - and Background's own
    // wallpaper Image, which asks for it the same way - waits on one decode, and
    // a surface created after that decode is Ready in the frame it is built. It
    // also stops a drag re-requesting the wallpaper on every pixel of travel:
    // only the sample rect below moves now.
    Image {
        id: wallpaperImage
        width: root.screenWidth
        height: root.screenHeight
        source: root.liveWallpaperActive ? "" : root.wallpaperUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
    }

    // One sampler for both paths: the source is whole-screen either way, and
    // the rect is where this surface sits on the monitor.
    ShaderEffectSource {
        id: wallpaperSample
        anchors.fill: parent
        visible: false
        live: true
        hideSource: false
        sourceItem: root.liveWallpaperActive ? root.weSurfaceItem : wallpaperImage
        sourceRect: Qt.rect(root.surfaceX, root.surfaceY,
            Math.max(1, root.width), Math.max(1, root.height))
    }

    FastBlur {
        anchors.fill: parent
        source: wallpaperSample
        radius: root.blurRadius
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: root._mask
        }
    }
}
