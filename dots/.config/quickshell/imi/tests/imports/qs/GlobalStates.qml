pragma Singleton

import QtQuick
import Quickshell

Singleton {
    property bool screenLocked: false
    // The lock look, as PluginState.currentSurface reads it: a test flips
    // this to move the default surface to the lock.
    property bool editLockPreview: false
    property bool lockLookActive: screenLocked || editLockPreview
    property bool editMode: false
}
