import QtQuick
import Quickshell
import qs.services
import qs.modules.common

/**
 * Drives services/Notes.qml's real migration against real files.
 *
 * tests/tst_notes_store.qml covers every shape the two stores can be in, but
 * it calls pure functions - it cannot see the part that actually decides
 * whether a user keeps their notes: two asynchronous FileView loads plus an
 * asynchronous Config load, all three of which have to be in hand before
 * anything is written, and a marker that must be set exactly once.
 *
 * Launched once per case by tests/test_notes_migration_runtime.py, which seeds
 * a throwaway XDG_STATE_HOME/XDG_CONFIG_HOME, passes the expected note bodies
 * in NOTES_EXPECT, and checks the files afterwards. Never point it at a real
 * state directory - it writes the note store.
 *
 *   NOTES_EXPECT='["a","b"]' XDG_CONFIG_HOME=$(mktemp -d) \
 *     XDG_STATE_HOME=$(mktemp -d) qs -p NotesMigrationRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int elapsed: 0

    readonly property var expected: JSON.parse(Quickshell.env("NOTES_EXPECT") ?? "[]")

    function check(label, ok) {
        console.log(`[NotesMigration] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[NotesMigration] failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    Timer {
        id: waitForStore
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForStore.interval;
            if (!Notes.ready) {
                if (harness.elapsed >= 15000) {
                    harness.check("the note store becomes ready", false);
                    harness.finish();
                }
                return;
            }
            waitForStore.running = false;

            const bodies = Notes.list.map(note => note.content);
            harness.check(`notes are ${JSON.stringify(harness.expected)}, got ${JSON.stringify(bodies)}`,
                          JSON.stringify(bodies) === JSON.stringify(harness.expected));
            harness.check("every note has an id",
                          Notes.list.every(note => typeof note.id === "string" && note.id.length > 0));
            harness.check("note ids are unique",
                          new Set(Notes.list.map(note => note.id)).size === Notes.list.length);
            harness.check("the legacy import marker is set",
                          Config.options.notes.importedLegacyStore === true);
            harness.check("the store points at notesPath",
                          Notes.filePath === Directories.notesPath);

            // Writing has to survive the migration: the surfaces call these,
            // and a store that loads but cannot be added to is still broken.
            const id = Notes.addNote("added by the harness");
            harness.check("a note can be added after migration",
                          id !== null && Notes.list.length === harness.expected.length + 1);
            Notes.deleteNote(id);
            harness.check("and deleted again", Notes.list.length === harness.expected.length);

            // The write is debounced inside Quickshell, so give it a moment
            // before the caller reads the file back.
            settle.running = true;
        }
    }

    Timer {
        id: settle
        interval: 750
        onTriggered: harness.finish()
    }
}
