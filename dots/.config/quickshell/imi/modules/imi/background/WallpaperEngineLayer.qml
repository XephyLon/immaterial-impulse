import QtQuick
import Quickshell.WallpaperEngine
import qs.modules.common

// Thin wrapper around the embedded Wallpaper Engine surface. Kept in its own
// file and loaded via a source-URL Loader so that on a Quickshell binary
// WITHOUT the Quickshell.WallpaperEngine module compiled in (the stock build),
// only this Loader fails - the rest of Background.qml, and the static-image
// wallpaper path, keep working.
WallpaperEngineSurface {
    id: root
    live: true
    fps: Config.options.wallpaperSelector.wallpaperEngine.fps
    // "fill" | "fit" | "stretch" | "default" - how the wallpaper is scaled to
    // the screen (user-selectable, mirrors the static-wallpaper scaling).
    scaleMode: Config.options.wallpaperSelector.wallpaperEngine.scaling

    // Set by Background.qml when a fullscreen window covers THIS output, and
    // forwarded to the surface's `occluded` below. Kept as a plain local
    // property so the binding in Background.qml always has something to target,
    // whether or not the binary underneath understands occlusion.
    property bool covered: false

    // The selector's volume button toggles `silent`. `audioEnabled` only exists
    // on newer qs-wallpaperengine builds, so bind it dynamically - on an older
    // binary this is a silent no-op instead of a load-breaking assignment.
    // Toggling reloads the wallpaper inside WE (audio is a load-time decision
    // there); brief black-out on toggle is expected.
    Component.onCompleted: {
        if ("audioEnabled" in root) {
            root.audioEnabled = Qt.binding(() =>
                !(Config.options.wallpaperSelector.wallpaperEngine.silent ?? true));
        }
        // `occluded` idles the RENDER THREAD while this output is covered, which
        // is the half QML cannot otherwise reach: suppressing the contents stops
        // Qt drawing the surface, but the WE thread keeps producing frames
        // behind it. Same dynamic-binding treatment as audioEnabled, and for the
        // same reason - it only exists on qs-wallpaperengine builds newer than
        // the one currently pinned, so on today's binary this is a no-op and the
        // pause still comes from WE's own detector.
        //
        // Scope: this does not reach mpv. A video wallpaper keeps decoding,
        // because only WE's private setPause() stops that. What it drops is the
        // blit, the fence, the publish, the repaint and the surface commit.
        if ("occluded" in root) {
            root.occluded = Qt.binding(() => root.covered);
        }
    }
}
