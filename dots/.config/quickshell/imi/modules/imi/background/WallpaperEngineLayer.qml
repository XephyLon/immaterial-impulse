import QtQuick
import Quickshell.WallpaperEngine
import qs.modules.common
import qs.services

// Thin wrapper around the embedded Wallpaper Engine surface. Kept in its own
// file and loaded via a source-URL Loader so that on a Quickshell binary
// WITHOUT the Quickshell.WallpaperEngine module compiled in (the stock build),
// only this Loader fails - the rest of Background.qml, and the static-image
// wallpaper path, keep working.
WallpaperEngineSurface {
    id: root
    live: true
    // Through the per-project override resolution, not the raw config: a
    // project with settings of its own (WallpaperEngineOverrides) runs at
    // those, every other project at the globals exactly as before.
    fps: WallpaperEngineOverrides.active.fps
    // "fill" | "fit" | "stretch" | "default" - how the wallpaper is scaled to
    // the screen (user-selectable, mirrors the static-wallpaper scaling).
    scaleMode: WallpaperEngineOverrides.active.scaling

    // Set by Background.qml when a fullscreen window covers THIS output, and
    // forwarded to the surface's `occluded` below. Kept as a plain local
    // property so the binding in Background.qml always has something to target,
    // whether or not the binary underneath understands occlusion.
    property bool covered: false

    // Whether THIS output is the one that plays the wallpaper's sound. Set by
    // Background.qml, which is the only thing that knows which screen this
    // surface is on. It used to be read straight off the `silent` config here,
    // and since there is one of these per output, every monitor played the
    // same track at once - #338.
    property bool audioWanted: false

    // The selector's volume button toggles `silent`. `audioEnabled` only exists
    // on newer qs-wallpaperengine builds, so bind it dynamically - on an older
    // binary this is a silent no-op instead of a load-breaking assignment.
    // Toggling reloads the wallpaper inside WE (audio is a load-time decision
    // there); brief black-out on toggle is expected.
    Component.onCompleted: {
        if ("audioEnabled" in root) {
            root.audioEnabled = Qt.binding(() => root.audioWanted);
        }
        // The rest of the engine's flag set (qs-wallpaperengine 0.3+), bound
        // dynamically for the same reason as audioEnabled: on an older binary
        // each absent property is a silent no-op instead of a load-breaking
        // assignment, and the sidebar hides the controls it cannot honour
        // (WallpaperEngineFeatures reports which of these exist).
        if ("volume" in root) {
            root.volume = Qt.binding(() => WallpaperEngineOverrides.active.volume);
        }
        if ("audioProcessing" in root) {
            root.audioProcessing = Qt.binding(() => WallpaperEngineOverrides.active.audioProcessing);
        }
        if ("mouseDisabled" in root) {
            root.mouseDisabled = Qt.binding(() => WallpaperEngineOverrides.active.disableMouse);
        }
        if ("parallaxDisabled" in root) {
            root.parallaxDisabled = Qt.binding(() => WallpaperEngineOverrides.active.disableParallax);
        }
        if ("particlesDisabled" in root) {
            root.particlesDisabled = Qt.binding(() => WallpaperEngineOverrides.active.disableParticles);
        }
        if ("properties" in root) {
            root.properties = Qt.binding(() => WallpaperEngineOverrides.active.properties);
        }
        // The "fill" crop position, live: the renderer reads it every frame,
        // so a drag on the picker pans the wallpaper with no reload.
        if ("focusX" in root) {
            root.focusX = Qt.binding(() => WallpaperEngineOverrides.active.focus.x);
        }
        if ("focusY" in root) {
            root.focusY = Qt.binding(() => WallpaperEngineOverrides.active.focus.y);
        }
        // `occluded` idles the RENDER THREAD while this output is covered, which
        // is the half QML cannot otherwise reach: suppressing the contents stops
        // Qt drawing the surface, but the WE thread keeps producing frames
        // behind it. Same dynamic-binding treatment as audioEnabled, and for the
        // same reason - the property only exists on WE-capable builds, so a
        // stock binary degrades to no pause instead of a load error.
        //
        // Since qs-wallpaperengine v0.2.6 it reaches mpv too: the renderer
        // forwards the flag into WE's own pause machinery, so video decode
        // stops while the output is covered (qs-wallpaperengine#19 - before
        // that, a 7680x2160 software-decoded video kept ~180% CPU behind a
        // fullscreen game). On v0.2.2-v0.2.5 the same binding only drops the
        // blit, fence, publish, repaint and surface commit.
        if ("occluded" in root) {
            root.occluded = Qt.binding(() => root.covered);
        }
    }
}
