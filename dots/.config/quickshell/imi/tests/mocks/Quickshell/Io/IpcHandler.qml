import QtQuick

// Minimal stand-in so singletons that expose an IpcHandler (e.g. PluginState,
// WallpaperEngine) still compile under qmltestrunner, which has no Quickshell
// runtime. The handler's own functions are declared on the instance, so the
// base only needs to accept the target property.
QtObject {
    property string target: ""
}
