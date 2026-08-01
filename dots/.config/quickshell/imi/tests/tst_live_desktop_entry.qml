import QtQuick
import QtTest
import Quickshell
import qs.modules.common.widgets

TestCase {
    name: "LiveDesktopEntryTest"

    function init() {
        // DesktopEntries is a singleton shared across every test function in this
        // file - reset it so tests can't see each other's entries.
        DesktopEntries.mockSetEntries([]);
    }

    function test_entryIsNullBeforeApplicationsLoad() {
        let resolver = createTemporaryObject(liveDesktopEntryComponent, this, { appId: "kitty" });
        compare(resolver.entry, null);
    }

    function test_entryUpdatesWhenApplicationsChangedFiresLate() {
        let resolver = createTemporaryObject(liveDesktopEntryComponent, this, { appId: "kitty" });
        compare(resolver.entry, null);

        // Simulates DesktopEntries.applications finishing its scan after the
        // resolver was already created - the real-world timing that left
        // DragApps.qml's pinned launcher permanently stuck with a null entry.
        DesktopEntries.mockSetEntries([{ id: "kitty", name: "Kitty" }]);

        compare(resolver.entry.id, "kitty");
    }

    function test_entryStaysNullForNonMatchingId() {
        let resolver = createTemporaryObject(liveDesktopEntryComponent, this, { appId: "org.kde.dolphin" });
        DesktopEntries.mockSetEntries([{ id: "kitty", name: "Kitty" }]);
        compare(resolver.entry, null);
    }

    function test_entryUpdatesWhenAppIdChanges() {
        DesktopEntries.mockSetEntries([
            { id: "kitty", name: "Kitty" },
            { id: "zen", name: "Zen Browser" }
        ]);
        let resolver = createTemporaryObject(liveDesktopEntryComponent, this, { appId: "kitty" });
        compare(resolver.entry.id, "kitty");

        resolver.appId = "zen";
        compare(resolver.entry.id, "zen");
    }

    Component {
        id: liveDesktopEntryComponent
        LiveDesktopEntry {}
    }
}
