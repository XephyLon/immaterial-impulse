pragma Singleton
import QtQuick

// Mocks the timing behavior that matters for LiveDesktopEntry: heuristicLookup() is a
// plain invokable (not a property), and the real applications list only populates some
// time after startup. mockSetEntries() lets a test simulate that late population by
// reassigning applications, which fires its own auto-generated applicationsChanged -
// the same signal production code connects to.
QtObject {
    id: root
    property var applications: ({ values: [] })

    function heuristicLookup(id) {
        return root.applications.values.find(e => e.id === id) ?? null
    }

    function mockSetEntries(list) {
        root.applications = { values: list }
    }
}
