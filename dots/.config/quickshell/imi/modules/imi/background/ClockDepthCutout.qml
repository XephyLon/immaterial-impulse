import QtQuick
import Qt5Compat.GraphicalEffects
import "../../common/functions/clockDepth.js" as ClockDepthLogic

/**
 * The wallpaper's subject, cut out of the wallpaper by its mask.
 *
 * One component because there are two call sites that must never be able to
 * disagree: Background.qml draws this over the desktop widgets, and the
 * wallpaper selector's picker draws it to ask the user whether the cutout is
 * any good. Those were two hand-written copies of the same stack - the same
 * `coverRect` call, the same clipping mask surface, the same OpacityMask -
 * which is a visualizer that can drift from the thing it exists to judge, and
 * a visualizer that disagrees with the layer is worse than none: it certifies
 * a mask against a registration the desktop never uses.
 *
 * Everything geometric about the registration is here and nowhere else;
 * `tests/lint_clock_depth_geometry.py` fails the suite on a second caller of
 * `coverRect`.
 */
Item {
    id: root

    // The wallpaper ITEM's own source, never a config path. A switch assigns
    // the wallpaper item's source imperatively so it can snapshot the outgoing
    // frame first, so reading the path would put the incoming image under the
    // outgoing image's mask for the length of every switch.
    property url wallpaperSource
    property string maskPath: ""
    // A token that changes when the mask file's bytes do, hung on the URL as a
    // fragment. Qt caches a pixmap by URL and a mask is rewritten at the SAME
    // path twice over - once per click while a subject is being selected, and
    // again when a second candidate is accepted for the same wallpaper.
    // Measured with a qml6 probe: a 32x8 image rewritten at 99x17 and
    // re-assigned to the identical URL still reported 32x8, and clearing the
    // source to "" first did not help either; with a fragment it loaded the new
    // bytes. The fragment is not part of the filename, so nothing else about
    // the load changes. The producer owns the token, as it owns the key.
    property string maskRevision: ""

    // The registered mask surface, exposed so an inspector can draw over the
    // SAME item rather than rebuild a second one from the same numbers - which
    // is the drift this component exists to make impossible.
    readonly property alias maskSurface: maskSurface
    readonly property alias maskStatus: mask.status
    readonly property alias wallpaperStatus: cutoutWallpaper.status
    // The un-squashed mask rectangle, in this item's coordinates. Usually
    // larger than the item and offset negatively, because most of the point is
    // that the picture is bigger than the box that crops it.
    readonly property rect maskRect: Qt.rect(mask.x, mask.y, mask.width, mask.height)
    readonly property size wallpaperSourceSize: Qt.size(cutoutWallpaper.implicitWidth,
        cutoutWallpaper.implicitHeight)

    Image {
        id: cutoutWallpaper
        anchors.fill: parent
        // Every one of these matches the `wallpaper` item inside the viewport
        // on purpose. Same source, same size, same fill mode means the
        // per-screen crop matches with no geometry of its own - and it means
        // Qt's image cache serves both from ONE decode, since a fill mode's
        // aspect flags are part of the request and a Stretch copy of the same
        // file would decode all over again.
        source: root.wallpaperSource
        fillMode: Image.PreserveAspectCrop
        cache: true
        smooth: true
        asynchronous: true
        // Drawn by the OpacityMask below, not by itself.
        visible: false
    }

    Item {
        id: maskSurface
        anchors.fill: parent
        visible: false
        // The mask is drawn oversized and offset (see coverRect), and this is
        // what crops it back to the wallpaper's box - the same crop
        // PreserveAspectCrop applies to the image it masks.
        clip: true

        Image {
            id: mask
            // The mask covers the whole picture, at whatever size and shape
            // the producer stored it (aspect-true, 4096 on the long side, now;
            // the model's own 1024 square before, which was NOT the
            // wallpaper's aspect and would have stretched 3.5x differently
            // from the image it masks if filled into the same box). Stretched
            // into the rectangle the whole wallpaper would occupy if nothing
            // clipped it, undoing the mask's resample and re-applying the crop
            // are the same operation - so the mask's shape never matters here.
            //
            // What masks is this file's ALPHA - Qt's OpacityMask reads nothing
            // else, so the producer writes the mask into the alpha channel as
            // well as the luminance. A plain grayscale mask is opaque
            // everywhere and lets the whole wallpaper through, which draws the
            // picture flat over the clock rather than the subject behind it.
            readonly property var coverRect: ClockDepthLogic.coverRect(
                cutoutWallpaper.implicitWidth, cutoutWallpaper.implicitHeight,
                maskSurface.width, maskSurface.height)
            x: mask.coverRect.x
            y: mask.coverRect.y
            width: mask.coverRect.width
            height: mask.coverRect.height
            source: root.maskPath === "" ? ""
                : `file://${root.maskPath}${root.maskRevision === "" ? "" : "#" + root.maskRevision}`
            fillMode: Image.Stretch
            smooth: true
            asynchronous: true
        }
    }

    // The one thing that paints. A missing or corrupt mask leaves this with an
    // Image.Error maskSource, which shows nothing rather than showing
    // everything - the right failure direction, and the reason the layer
    // degrades to today's flat clock instead of to a wallpaper pasted over it.
    OpacityMask {
        anchors.fill: parent
        source: cutoutWallpaper
        maskSource: maskSurface
    }
}
