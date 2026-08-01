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
    }
}
