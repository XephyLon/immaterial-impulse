import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
// Both surfaces are loaded by URL, and a qs.* module only resolves for them
// once something in the loaded tree has imported it - so import the overlay
// module here even though this file uses no type from it directly.
import qs.modules.imi.overlay

/**
 * Builds the two real notes surfaces - the bundled notes plugin widget and the
 * overlay notes editor - side by side over one store, and drives them with
 * real mouse events.
 *
 * The question no static check can answer is the one this feature is about:
 * the two surfaces share a file, so a note added in one has to be in the
 * other, and the delete button has to actually delete rather than merely
 * exist. `import QtTest` works inside `qs -p`, so the clicks here are real
 * events with no ydotool involved.
 *
 * Both surfaces are ordinary Items, so a FloatingWindow is enough - no
 * layer-shell, which means this runs under headless weston too.
 *
 * Run it against throwaway state, never a real one - it writes the note store:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) \
 *     qs -p NotesSurfacesRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int elapsed: 0

    function check(label, ok) {
        console.log(`[NotesSurfaces] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[NotesSurfaces] failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    TestCase {
        id: driver
        when: false
        name: "NotesSurfacesDriver"
    }

    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 800
        implicitHeight: 420
        color: "black"

        Loader {
            id: widgetLoader
            x: 0
            y: 0
            width: 276
            height: 228
            source: Qt.resolvedUrl("modules/common/plugins/bundled/notes/Widget.qml")
        }

        Loader {
            id: overlayLoader
            x: 300
            y: 0
            width: 460
            height: 330
            source: Qt.resolvedUrl("modules/imi/overlay/notes/NotesContent.qml")
        }
    }

    // Clicks the centre of `item`. QtTest wants coordinates relative to the
    // item it is handed, so map into a common ancestor first.
    function clickItem(receiver, item) {
        const point = item.mapToItem(receiver, item.width / 2, item.height / 2);
        driver.mouseClick(receiver, point.x, point.y, Qt.LeftButton);
    }

    function widget() {
        return widgetLoader.item;
    }

    function overlay() {
        return overlayLoader.item;
    }

    function noteList() {
        return harness.findByName(widget(), "notesList");
    }

    function findByName(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (let i = 0; i < item.children.length; i++) {
            const found = harness.findByName(item.children[i], name);
            if (found)
                return found;
        }
        return null;
    }

    Timer {
        id: waitForStore
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForStore.interval;
            if (!Notes.ready || !widgetLoader.item || !overlayLoader.item) {
                if (harness.elapsed >= 15000) {
                    harness.check("both surfaces load against a ready store", false);
                    harness.finish();
                }
                return;
            }
            waitForStore.running = false;
            harness.check("both surfaces load against a ready store", true);
            harness.check("the store starts empty", Notes.list.length === 0);
            step1.running = true;
        }
    }

    // A note written through the overlay editor must show up in the widget.
    Timer {
        id: step1
        interval: 300
        onTriggered: {
            overlay().startNewNote();
            overlay().content = "written in the overlay";
            overlay().saveContent();

            harness.check("the overlay creates a note", Notes.list.length === 1);
            harness.check("the widget's list sees it",
                          harness.noteList()?.count === 1);
            harness.check("the widget shows the overlay's text",
                          Notes.list[0].content === "written in the overlay");
            step2.running = true;
        }
    }

    // ... and the reverse: the widget's add button, driven by a real click.
    Timer {
        id: step2
        interval: 300
        onTriggered: {
            const addButton = harness.findByName(widget(), "addNoteButton");
            harness.check("the widget has an add button", addButton !== null);
            harness.clickItem(widgetLoader, addButton);
            step3.running = true;
        }
    }

    Timer {
        id: step3
        interval: 500
        onTriggered: {
            harness.check("clicking add opens the editor", widget().mode === "edit");

            const editArea = harness.findByName(widget(), "editArea");
            harness.check("the editor never renders a note as markup",
                          editArea?.textFormat === TextEdit.PlainText);
            editArea.text = "written in the widget";

            const saveButton = harness.findByName(widget(), "saveNoteButton");
            harness.clickItem(widgetLoader, saveButton);
            step4.running = true;
        }
    }

    Timer {
        id: step4
        interval: 500
        onTriggered: {
            harness.check("the widget's save adds a note", Notes.list.length === 2);
            harness.check("and returns to the list", widget().mode === "list");
            harness.check("the overlay sees the widget's note",
                          Notes.list.some(note => note.content === "written in the widget"));

            // Editing an existing note through the overlay, not just creating
            // one: the widget row has to follow it.
            const widgetNote = Notes.list.find(note => note.content === "written in the widget");
            overlay().selectNote(widgetNote.id);
            harness.check("the overlay opens the note the widget wrote",
                          overlay().content === "written in the widget");
            overlay().content = "edited in the overlay";
            overlay().saveContent();
            harness.check("the overlay's edit reaches the store",
                          Notes.noteById(widgetNote.id)?.content === "edited in the overlay");

            // Deleting from the overlay must remove it from the widget's list,
            // not just from the overlay's own view.
            overlay().selectNote(Notes.list[0].id);
            overlay().deleteCurrentNote();
            step5.running = true;
        }
    }

    Timer {
        id: step5
        interval: 400
        onTriggered: {
            harness.check("the overlay's delete removes the note", Notes.list.length === 1);
            harness.check("the widget's list drops it too", harness.noteList()?.count === 1);
            harness.check("the overlay moved to the surviving note",
                          overlay().currentNoteId === Notes.list[0].id);

            // And the widget's own per-row delete button.
            const deleteButton = harness.findByName(widget(), "deleteNoteButton");
            harness.check("the widget has a per-note delete button", deleteButton !== null);
            harness.clickItem(widgetLoader, deleteButton);
            step6.running = true;
        }
    }

    Timer {
        id: step6
        interval: 500
        onTriggered: {
            harness.check("clicking it empties the store", Notes.list.length === 0);
            harness.check("and the overlay clears with it",
                          overlay().currentNoteId === "");
            harness.finish();
        }
    }
}
