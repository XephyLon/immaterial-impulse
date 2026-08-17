pragma Singleton
import QtQuick

// A logic-only stand-in for the real PluginManager, on the Directories.qml
// precedent: the real one scans manifests through FileView/Process at
// construction, which a unit test neither needs nor can feed. The one surface
// BarWidgets reads is `availablePlugins`, left writable so a test can drive
// an install/uninstall and prove the catalogue follows it.
QtObject {
    property var availablePlugins: []
}
