import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

// In-shell blur backdrop for desktop widgets (plugins + the User Card). Samples
// the wallpaper region directly behind this surface and blurs it, so the widget
// reads as frosted glass over the wallpaper.
//
// Both wallpaper paths are one shape: an item covering the whole wallpaper,
// sampled at this surface's rect through a ShaderEffectSource.
//
// - Live Wallpaper Engine wallpaper: the in-shell WallpaperEngineSurface
//   (weSurfaceItem). WE is now drawn on the background surface itself, so the
//   old compositor-blur handoff no longer applies - we blur the live frame
//   ourselves.
// - Static image wallpaper: an Image of the wallpaper, cover-fitted exactly as
//   the desktop draws it (see wallpaperImage).
//
// The rect and the item it is handed to must be in the SAME space, and that
// space is the wallpaper's, not the screen's - see surfaceX/surfaceY. The
// caller owns that conversion (ParallaxMath.sampleOrigin); this component only
// promises to sample where it is told, in an item of the size it is given.
Item {
    id: root

    property string wallpaperSource: ""
    property bool liveWallpaperActive: false
    // The live WallpaperEngineSurface item (whole-screen), sampled for the live
    // path. Null for the static path.
    property Item weSurfaceItem: null
    property real cornerRadius: Appearance.rounding?.verylarge ?? 30
    property int blurRadius: 48

    // The size of the wallpaper the frost samples, and this surface's top-left
    // WITHIN it - not on the monitor. With parallax the wallpaper is drawn in a
    // container larger than the screen and slid underneath it, so the two are
    // different by both pans; the static reconstruction below has to be the
    // same size as that container, or it is a different crop of the same file
    // than the one on screen. ParallaxMath.sampleOrigin does the conversion.
    property real wallpaperWidth: 0
    property real wallpaperHeight: 0
    property real surfaceX: 0
    property real surfaceY: 0

    readonly property string wallpaperUrl: root.wallpaperSource
        ? "file://" + root.wallpaperSource.split('/').map(s => encodeURIComponent(s)).join('/')
        : ""

    // Load state of the static sample. The cascade this component exists to
    // avoid is only observable as *when* each surface's wallpaper arrives, and
    // nothing else about the frost is reachable from a test - see
    // tests/tst_wallpaper_blur_sharing.qml.
    readonly property int sampleStatus: wallpaperImage.status

    // The frost's shape. By default a rounded rectangle built from
    // `cornerRadius` - which is why, historically, a frosted card could *only*
    // be a rounded rectangle: this was the one mask there was. A caller whose
    // card is not a rounded rect (a MaterialShape card, morphing or settled)
    // supplies its own mask item instead; OpacityMask only reads alpha, so any
    // item drawing the card's outline serves. The fallback keeps every
    // existing region record working untouched.
    property Item maskItem: null

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
        width: root.wallpaperWidth
        height: root.wallpaperHeight
        source: root.liveWallpaperActive ? "" : root.wallpaperUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
    }

    // One sampler for both paths: the source covers the whole wallpaper either
    // way, and the rect is where this surface sits within it.
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
            maskSource: root.maskItem ?? root._mask
        }
    }
}
