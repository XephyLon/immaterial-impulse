pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick
import "../modules/common/functions/notesStore.js" as NotesStore

/**
 * The note store: a JSON array of { id, content, attachments, createdAt } in
 * Directories.notesPath.
 *
 * Single owner on purpose. The bundled notes plugin is instantiated once per
 * monitor and the overlay notes editor is a third surface onto the same data;
 * a singleton is what makes "add a note here, see it there" true by
 * construction instead of by three FileViews racing each other over one file.
 * That also means no `watchChanges` is needed for the surfaces to agree - they
 * are all reading this object, not the file.
 *
 * Directories.notesPath, not desktopNotesPath, because notes.txt is the store
 * both live surfaces have been writing since the built-in widget was deleted.
 * The array's historical home is imported into it once (see the migration
 * below) rather than the other way around, so nobody's scratchpad has to be
 * moved out from under them.
 */
Singleton {
    id: root
    property string filePath: Directories.notesPath
    property string legacyFilePath: Directories.desktopNotesPath
    property var list: []

    // True once the store on disk has been read and migrated. Writers are
    // gated on it: an add/update/delete before the load lands would serialize
    // the empty startup array over the user's real notes.
    property bool ready: false

    property bool primaryLoaded: false
    property bool legacyLoaded: false
    property string primaryText: ""
    property string legacyText: ""

    function addNote(content, attachments) {
        if (!root.ready)
            return null;
        const item = {
            "id": NotesStore.makeId(),
            "content": content ?? "",
            "attachments": attachments ?? [],
            "createdAt": Date.now()
        };
        const next = root.list.slice(0);
        next.push(item);
        root.commit(next);
        return item.id;
    }

    function updateNote(id, content, attachments) {
        if (!root.ready)
            return;
        const next = root.list.slice(0);
        const idx = next.findIndex(note => note.id === id);
        if (idx < 0)
            return;
        // Copy the note as well as the array: delegates hold references to
        // these objects, and mutating one in place leaves a ListView showing
        // the old text until something else forces it to re-read the model.
        const updated = {
            "id": next[idx].id,
            "content": content ?? "",
            "attachments": attachments === undefined ? next[idx].attachments : attachments,
            "createdAt": next[idx].createdAt
        };
        if (updated.content === next[idx].content && attachments === undefined)
            return;
        next[idx] = updated;
        root.commit(next);
    }

    function deleteNote(id) {
        if (!root.ready)
            return;
        const next = root.list.filter(note => note.id !== id);
        if (next.length === root.list.length)
            return;
        root.commit(next);
    }

    function noteById(id) {
        return root.list.find(note => note.id === id) ?? null;
    }

    function commit(notes) {
        root.list = notes;
        notesFileView.setText(JSON.stringify(root.list));
    }

    // Both stores and the marker have to be in hand before anything is
    // written: the marker says whether the legacy store may still be imported,
    // and Config loads asynchronously just like the files do.
    function tryMigrate() {
        if (root.ready || !root.primaryLoaded || !root.legacyLoaded || !Config.ready)
            return;

        const importLegacy = !Config.options.notes.importedLegacyStore;
        const result = NotesStore.migrate(root.primaryText, root.legacyText, importLegacy);
        root.list = result.notes;
        root.ready = true;

        if (result.changed)
            notesFileView.setText(JSON.stringify(root.list));

        // Marker last, and only for the legacy half: a launch that dies
        // between the write and here migrates again next time (harmless - the
        // import dedupes on note id) rather than recording an import that
        // never reached the file.
        //
        // The legacy file itself is never touched. It is the user's only copy
        // of those notes if anything here is wrong, and it costs nothing to
        // leave it where it is.
        if (importLegacy) {
            if (result.importedLegacy)
                console.log(`[Notes] Imported the legacy desktop notes store from ${root.legacyFilePath}`);
            Config.options.notes.importedLegacyStore = true;
        }
    }

    Component.onCompleted: {
        notesFileView.reload();
        legacyNotesFileView.reload();
    }

    Connections {
        target: Config
        function onReadyChanged() {
            root.tryMigrate();
        }
    }

    FileView {
        id: notesFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            const text = notesFileView.text();
            if (root.ready) {
                // A reload after startup (an external edit, or our own write
                // echoing back) must not resurrect the pre-migration text.
                const reloaded = NotesStore.parseNoteArray(text);
                if (reloaded !== null)
                    root.list = reloaded;
                return;
            }
            root.primaryText = text;
            root.primaryLoaded = true;
            root.tryMigrate();
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.log(`[Notes] Error loading ${root.filePath}: ${error}`);
            root.primaryText = "";
            root.primaryLoaded = true;
            root.tryMigrate();
        }
    }

    // Read once, written never. The built-in desktop notes widget that filled
    // this file is gone; this is the only thing left that reads it.
    FileView {
        id: legacyNotesFileView
        path: Qt.resolvedUrl(root.legacyFilePath)
        onLoaded: {
            root.legacyText = legacyNotesFileView.text();
            root.legacyLoaded = true;
            root.tryMigrate();
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.log(`[Notes] Error loading ${root.legacyFilePath}: ${error}`);
            root.legacyText = "";
            root.legacyLoaded = true;
            root.tryMigrate();
        }
    }
}
