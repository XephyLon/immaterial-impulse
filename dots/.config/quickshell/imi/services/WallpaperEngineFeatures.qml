pragma Singleton
import QtQuick
import Quickshell

/**
 * What this binary's embedded Wallpaper Engine renderer can be asked. The
 * selector sidebar gates its extended controls on these, so a shell running
 * an older qs-wallpaperengine binary (or a stock Quickshell with no module at
 * all) shows exactly the controls the renderer answers - a control for a
 * flag the renderer does not read would be a fake action.
 *
 * Probed by building one bare WallpaperEngineSurface (no project, so no
 * thread and no GL) and asking which properties exist - the same question
 * WallpaperEngineLayer's dynamic bindings ask, from before any project is
 * live. The probe is loaded by URL so a binary without the module fails only
 * this Loader.
 */
Singleton {
    id: root

    readonly property bool engineFlags: probeLoader.item?.engineFlags ?? false
    readonly property bool projectProperties: probeLoader.item?.projectProperties ?? false

    Loader {
        id: probeLoader
        source: Qt.resolvedUrl("../modules/imi/background/WallpaperEngineProbe.qml")
    }
}
