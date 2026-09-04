import QtQuick
import QtTest
import qs.modules.common.widgets

// Desktop widget frost used to come back one widget at a time after anything
// that rebuilt the blur surfaces (#147): each surface asked for the wallpaper
// with request parameters of its own (a per-surface `sourceClipRect`, and
// `cache: false`), so no two requests could be shared and Qt's single
// pixmap-reader thread served them one after another - eight widgets, sixteen
// full-resolution decodes, ~0.6s each.
//
// Nothing about the rendered frost is reachable from a test: Quickshell's
// plugin does not load in qmltestrunner and the software scene graph draws no
// ShaderEffect. What *is* reachable is the load state that ordered the cascade,
// and it is the whole mechanism: a surface that shares the wallpaper request is
// Ready the moment it is built, and one that does not has to wait for a decode.
TestCase {
    name: "WallpaperBlurSharingTest"

    readonly property string wallpaperPath:
        Qt.resolvedUrl("fixtures/colorful_64.png").toString().replace("file://", "")

    // Stands in for Background.qml's own wallpaper Image, which has already
    // decoded the file by the time any desktop widget is built. Declared with
    // exactly that image's request parameters, because every one of them is part
    // of the cache key: a bare path rather than the file:// URL the surface
    // builds, no sourceClipRect, PreserveAspectCrop - a fill mode that preserves
    // aspect sets flags in the request, so the same file asked for with the
    // default Stretch is a different request and decodes again - and the
    // sourceSize bound. The bound is part of the key too, so the frost surface
    // has to ask with the same one or #147's per-surface decode comes back with
    // a different spelling.
    Image {
        id: backgroundWallpaper
        fillMode: Image.PreserveAspectCrop
        cache: true
        asynchronous: true
        visible: false
        sourceSize: Qt.size(5478, 1541)
    }

    Component {
        id: surfaceComponent
        WallpaperBlurSurface {}
    }

    function buildSurface(index) {
        return createTemporaryObject(surfaceComponent, this, {
            wallpaperSource: wallpaperPath,
            // The wallpaper's size, not the monitor's: with parallax the
            // wallpaper is drawn `zoom` times the screen (5120x1440 at 107%),
            // and the reconstruction has to occupy that same space or it is a
            // different crop of the same file than the one on screen. The
            // request is unchanged by it - the item's size is not part of a
            // pixmap cache key, which is what keeps #147 fixed.
            wallpaperWidth: 5478,
            wallpaperHeight: 1541,
            // The decode bound Background's own request carries - the fifth
            // request parameter, and like the others it must match exactly.
            decodeWidth: 5478,
            decodeHeight: 1541,
            surfaceX: 100 + index * 400,
            surfaceY: 220,
            width: 320,
            height: 200
        });
    }

    function test_everySurfaceSharesTheWallpaperTheDesktopAlreadyDecoded() {
        backgroundWallpaper.source = wallpaperPath;
        tryVerify(() => backgroundWallpaper.status === Image.Ready, 5000,
            "the stand-in background wallpaper never loaded");

        // Eight surfaces at eight different places on the monitor: the desktop
        // the cascade was measured on. Under the old shape each one issues its
        // own clipped decode and is still Loading here.
        for (let i = 0; i < 8; i++) {
            const surface = buildSurface(i);
            compare(surface.sampleStatus, Image.Ready,
                "surface " + i + " had to wait for a decode of its own");
        }
    }

    // The live Wallpaper Engine path samples the WE surface instead, so it must
    // not ask the image reader for anything at all - a live project has no file
    // to decode, and requesting the last static wallpaper behind it would put
    // the queue back for the path that never had it.
    function test_theLiveWallpaperPathRequestsNoImage() {
        const surface = buildSurface(0);
        surface.liveWallpaperActive = true;
        compare(surface.sampleStatus, Image.Null,
            "the live path still requested a static wallpaper");
    }
}
