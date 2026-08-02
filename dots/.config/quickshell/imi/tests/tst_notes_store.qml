import QtTest
import "../modules/common/functions/notesStore.js" as NotesStore

/**
 * The note store's parse/migration logic, which decides what a user still has
 * after the notes feature stopped being a single plaintext scratchpad and
 * became a JSON array.
 *
 * Every case here is a real on-disk state some install is in right now:
 * notes.txt holding plaintext, desktopnotes.txt holding the old array, both
 * holding something, either missing, either corrupt. The rule the whole suite
 * exists to enforce is that no branch may lose text - a file that cannot be
 * parsed becomes a note verbatim rather than being reset to empty, which is
 * what the deleted built-in service used to do to a corrupt file.
 */
TestCase {
    name: "NotesStoreTest"

    readonly property string arrayText: JSON.stringify([
        { id: "a1", content: "first", attachments: [], createdAt: 1000 },
        { id: "a2", content: "second", attachments: ["/tmp/x.png"], createdAt: 2000 }
    ])

    function test_parses_a_stored_note_array() {
        const notes = NotesStore.parseNoteArray(arrayText);
        compare(notes.length, 2);
        compare(notes[0].id, "a1");
        compare(notes[1].content, "second");
        compare(notes[1].attachments[0], "/tmp/x.png");
        compare(notes[1].createdAt, 2000);
    }

    function test_an_empty_array_is_a_migrated_store_not_a_failure() {
        const notes = NotesStore.parseNoteArray("[]");
        verify(notes !== null);
        compare(notes.length, 0);
    }

    // A scratchpad whose text happens to be JSON must not be mistaken for a
    // note array and silently reinterpreted as notes with no content.
    function test_json_that_is_not_notes_is_not_a_note_array() {
        compare(NotesStore.parseNoteArray("[1, 2, 3]"), null);
        compare(NotesStore.parseNoteArray('["shopping", "list"]'), null);
        compare(NotesStore.parseNoteArray('{"content": "not an array"}'), null);
        compare(NotesStore.parseNoteArray("not json at all"), null);
        compare(NotesStore.parseNoteArray(""), null);
    }

    function test_normalize_fills_in_what_an_old_note_lacks() {
        const note = NotesStore.normalizeNote({ id: 17, content: "hi" });
        compare(note.id, "17");
        compare(note.content, "hi");
        compare(note.attachments.length, 0);
        verify(note.createdAt > 0);
    }

    function test_plaintext_scratchpad_becomes_one_note_verbatim() {
        const result = NotesStore.migrate("buy milk\n- and eggs", "", true);
        compare(result.notes.length, 1);
        compare(result.notes[0].content, "buy milk\n- and eggs");
        verify(result.notes[0].id.length > 0);
        compare(result.changed, true);
    }

    function test_an_already_migrated_store_is_not_rewritten() {
        const result = NotesStore.migrate(arrayText, "", false);
        compare(result.notes.length, 2);
        compare(result.changed, false);
        compare(result.importedLegacy, false);
    }

    function test_legacy_desktop_notes_are_imported_when_the_marker_is_unset() {
        const legacy = JSON.stringify([{ id: "d1", content: "desktop note", attachments: [], createdAt: 5 }]);
        const result = NotesStore.migrate("[]", legacy, true);
        compare(result.notes.length, 1);
        compare(result.notes[0].id, "d1");
        compare(result.importedLegacy, true);
        compare(result.changed, true);
    }

    function test_legacy_desktop_notes_are_left_alone_once_the_marker_is_set() {
        const legacy = JSON.stringify([{ id: "d1", content: "desktop note", attachments: [], createdAt: 5 }]);
        const result = NotesStore.migrate(arrayText, legacy, false);
        compare(result.notes.length, 2);
        compare(result.importedLegacy, false);
        compare(result.changed, false);
    }

    // The case that decides whether anyone loses anything: content in BOTH
    // stores. Neither may win over the other.
    function test_content_in_both_stores_survives_together() {
        const legacy = JSON.stringify([
            { id: "d1", content: "desktop one", attachments: [], createdAt: 5 },
            { id: "d2", content: "desktop two", attachments: [], createdAt: 6 }
        ]);
        const result = NotesStore.migrate("scratchpad text", legacy, true);
        compare(result.notes.length, 3);
        compare(result.notes[0].content, "scratchpad text");
        compare(result.notes[1].content, "desktop one");
        compare(result.notes[2].content, "desktop two");
        compare(result.changed, true);
    }

    function test_an_empty_scratchpad_leaves_only_the_legacy_notes() {
        const legacy = JSON.stringify([{ id: "d1", content: "desktop note", attachments: [], createdAt: 5 }]);
        const result = NotesStore.migrate("", legacy, true);
        compare(result.notes.length, 1);
        compare(result.notes[0].content, "desktop note");
    }

    function test_both_stores_absent_yields_an_empty_store() {
        const result = NotesStore.migrate(null, null, true);
        compare(result.notes.length, 0);
        compare(result.importedLegacy, false);
    }

    function test_a_whitespace_only_store_does_not_become_a_blank_note() {
        const result = NotesStore.migrate("\n  \n", "   ", true);
        compare(result.notes.length, 0);
    }

    // Corruption must not be destructive. The old service reset a corrupt file
    // to `[]` and wrote that back, which threw the text away.
    function test_a_corrupt_scratchpad_is_kept_as_a_note() {
        const result = NotesStore.migrate('{"half written', "", true);
        compare(result.notes.length, 1);
        compare(result.notes[0].content, '{"half written');
    }

    function test_a_corrupt_legacy_store_is_kept_as_a_note() {
        const result = NotesStore.migrate("[]", '[{"id": "d1", "content": "trunc', true);
        compare(result.notes.length, 1);
        compare(result.notes[0].content, '[{"id": "d1", "content": "trunc');
        compare(result.importedLegacy, true);
    }

    // Belt and braces for a migration that runs twice (a launch that dies
    // between the write and the marker): the same legacy note must not appear
    // twice.
    function test_reimporting_the_same_legacy_note_does_not_duplicate_it() {
        const legacy = JSON.stringify([{ id: "d1", content: "desktop note", attachments: [], createdAt: 5 }]);
        const first = NotesStore.migrate("", legacy, true);
        const second = NotesStore.migrate(JSON.stringify(first.notes), legacy, true);
        compare(second.notes.length, 1);
        compare(second.notes[0].id, "d1");
    }

    function test_generated_ids_are_unique() {
        const ids = {};
        for (let i = 0; i < 50; i++) {
            const id = NotesStore.makeId();
            verify(ids[id] === undefined);
            ids[id] = true;
        }
    }
}
