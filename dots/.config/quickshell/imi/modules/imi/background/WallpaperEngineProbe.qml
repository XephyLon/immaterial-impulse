import QtQuick
import Quickshell.WallpaperEngine

// A bare WallpaperEngineSurface built only to be asked which properties this
// binary's renderer has. With no projectPath it starts no thread, no GL and
// no timer - construction is the whole cost. Loaded by URL from
// WallpaperEngineFeatures for the reason WallpaperEngineLayer is: on a
// Quickshell binary without the module, only the Loader fails.
Item {
    // The qs-wallpaperengine 0.3 flag set: volume, the audio-reactive
    // recorder, and WE's three feature disables. One bool for the group -
    // they shipped together, and a sidebar offering half of a set that
    // cannot exist is not a state worth expressing.
    readonly property bool engineFlags: ("volume" in probeSurface)
        && ("audioProcessing" in probeSurface)
        && ("mouseDisabled" in probeSurface)
        && ("parallaxDisabled" in probeSurface)
        && ("particlesDisabled" in probeSurface)

    // Per-wallpaper project.json property overrides (--set-property).
    readonly property bool projectProperties: "properties" in probeSurface

    // The live "fill" crop position - the section picker's renderer support.
    readonly property bool cropFocus: ("focusX" in probeSurface) && ("focusY" in probeSurface)

    // The full-scene grab the crop picker's accurate thumbnail needs.
    readonly property bool sceneGrab: "requestSceneGrab" in probeSurface

    // The render-scale quality dial (draw into a smaller window, upscale).
    readonly property bool renderScale: "renderScale" in probeSurface

    WallpaperEngineSurface {
        id: probeSurface
        visible: false
    }
}
