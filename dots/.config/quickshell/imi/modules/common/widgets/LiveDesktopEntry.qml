import Quickshell
import QtQuick

// DesktopEntries.heuristicLookup() is a plain invokable, not a property read, so a
// binding built from it never re-evaluates when DesktopEntries.applications changes.
// DesktopEntries.applications only populates a few seconds after startup, so anything
// that resolved its entry before that finished would be stuck with a null entry
// forever. This re-fetches explicitly on applicationsChanged so callers don't have to.
Item {
    id: root
    visible: false
    property string appId: ""
    property var entry: root.appId !== "" ? DesktopEntries.heuristicLookup(root.appId) : null

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.entry = root.appId !== "" ? DesktopEntries.heuristicLookup(root.appId) : null
        }
    }
}
