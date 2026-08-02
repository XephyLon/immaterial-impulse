.pragma library

// Parsing and migration for the note store: a JSON array of
// { id, content, attachments, createdAt } kept in Directories.notesPath and
// owned by services/Notes.qml.
//
// Two stores predate it and both may hold the only copy of something a user
// wrote: notes.txt held one plaintext scratchpad (the bundled notes plugin and
// the overlay notes editor shared it), desktopnotes.txt held this array (the
// deleted built-in notes widget). Everything here is written so that no input
// - including a corrupt one - ends with text on the floor. A file that cannot
// be understood becomes a note verbatim; it is never reset to empty.
//
// Pure functions on strings, so tests/tst_notes_store.qml can exercise every
// on-disk state without touching a disk.

var idCounter = 0;

// Unique within a session as well as across sessions: two notes created in the
// same millisecond (which the migration does, folding two stores at once) must
// not collide, or the dedup below would drop one of them.
function makeId() {
    idCounter++;
    return Date.now().toString() + "-" + idCounter + "-" + Math.floor(Math.random() * 10000);
}

function isNoteLike(value) {
    return value !== null
        && typeof value === "object"
        && !Array.isArray(value)
        && typeof value.content === "string";
}

function normalizeNote(value) {
    var id = "";
    if (value.id !== undefined && value.id !== null)
        id = String(value.id);
    return {
        "id": id.length > 0 ? id : makeId(),
        "content": typeof value.content === "string" ? value.content : "",
        "attachments": Array.isArray(value.attachments) ? value.attachments.slice(0) : [],
        "createdAt": typeof value.createdAt === "number" ? value.createdAt : Date.now()
    };
}

function noteFromText(text, createdAt) {
    return {
        "id": makeId(),
        "content": String(text),
        "attachments": [],
        "createdAt": createdAt === undefined ? Date.now() : createdAt
    };
}

// The note array, or null when `text` is anything else - including JSON that
// simply is not notes, so a scratchpad that happened to contain `[1, 2, 3]`
// is preserved as text rather than read as three contentless notes.
function parseNoteArray(text) {
    if (text === undefined || text === null || String(text).length === 0)
        return null;
    var parsed;
    try {
        parsed = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!Array.isArray(parsed))
        return null;
    if (!parsed.every(isNoteLike))
        return null;
    return parsed.map(normalizeNote);
}

// Anything a store holds, as notes: an array is its notes, any other non-blank
// text is one note carrying it verbatim, blank is nothing.
function notesFromStore(text) {
    var parsed = parseNoteArray(text);
    if (parsed !== null)
        return parsed;
    if (text === undefined || text === null || String(text).trim().length === 0)
        return [];
    return [noteFromText(text)];
}

/**
 * Fold both stores into one note array.
 *
 * `primaryText`  - contents of Directories.notesPath (the surviving store)
 * `legacyText`   - contents of Directories.desktopNotesPath
 * `importLegacy` - false once the one-shot legacy import has been recorded;
 *                  the legacy file stays on disk forever, so without this it
 *                  would be re-imported on every launch and deleted notes
 *                  would come back.
 *
 * Returns { notes, changed, importedLegacy }. `changed` means the caller must
 * write `notes` back: either the primary store was not already a note array,
 * or legacy notes were folded in.
 */
function migrate(primaryText, legacyText, importLegacy) {
    var primary = parseNoteArray(primaryText);
    var notes = primary !== null ? primary : notesFromStore(primaryText);
    var changed = primary === null;
    var importedLegacy = false;

    if (importLegacy) {
        var seen = {};
        notes.forEach(function (note) {
            seen[note.id] = true;
        });
        notesFromStore(legacyText).forEach(function (note) {
            importedLegacy = true;
            if (seen[note.id])
                return;
            seen[note.id] = true;
            notes.push(note);
            changed = true;
        });
    }

    return {
        "notes": notes,
        "changed": changed,
        "importedLegacy": importedLegacy
    };
}
