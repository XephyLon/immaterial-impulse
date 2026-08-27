import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.overlay

/**
 * The overlay notes editor.
 *
 * It edits one note of services/Notes.qml's array at a time, chosen from the
 * strip of chips along the top. It used to own a plaintext file directly -
 * the same file the bundled notes plugin owned - which is why both had to move
 * to the array together: one surface on plaintext and one on JSON would have
 * been two notes surfaces silently disagreeing about what the user wrote.
 */
OverlayBackground {
    id: root

    property alias content: textInput.text
    property var copyListEntries: []
    property string lastParsedCopylistText: ""
    property var parsedCopylistLines: []
    property bool isClickthrough: false
    property real maxCopyButtonSize: 20

    // The note being edited. Empty while composing one that does not exist
    // yet: `composingNew` keeps the selection from snapping back to an
    // existing note before the first save creates it.
    property string currentNoteId: ""
    property bool composingNew: false

    Component.onCompleted: {
        syncSelection();
        updateCopyListEntries();
    }

    function notePreview(text) {
        const firstLine = String(text ?? "").split("\n").find(line => line.trim().length > 0) ?? "";
        const trimmed = firstLine.trim();
        if (trimmed.length === 0)
            return Translation.tr("Untitled");
        return trimmed.length > 18 ? trimmed.slice(0, 17) + "…" : trimmed;
    }

    function saveContent() {
        if (!textInput || !Notes.ready)
            return;
        if (root.currentNoteId.length === 0) {
            if (root.content.trim().length === 0)
                return;
            root.currentNoteId = Notes.addNote(root.content);
            root.composingNew = false;
            return;
        }
        Notes.updateNote(root.currentNoteId, root.content);
    }

    function flushPendingSave() {
        if (!saveDebounce.running)
            return;
        saveDebounce.stop();
        saveContent();
    }

    function loadCurrentNote() {
        const note = Notes.noteById(root.currentNoteId);
        const text = note ? note.content : "";
        if (textInput.text !== text)
            textInput.text = text;
        Qt.callLater(root.updateCopyListEntries);
    }

    // Keeps a selection pointing at a note that still exists - the note may
    // have been deleted from the desktop widget while this editor was open.
    function syncSelection() {
        if (!Notes.ready || root.composingNew)
            return;
        if (Notes.noteById(root.currentNoteId) !== null)
            return;
        root.currentNoteId = Notes.list.length > 0 ? Notes.list[0].id : "";
        loadCurrentNote();
    }

    function selectNote(id) {
        if (id === root.currentNoteId && !root.composingNew)
            return;
        flushPendingSave();
        root.composingNew = false;
        root.currentNoteId = id;
        loadCurrentNote();
    }

    function startNewNote() {
        flushPendingSave();
        root.currentNoteId = "";
        root.composingNew = true;
        textInput.text = "";
        focusAtEnd();
    }

    function deleteCurrentNote() {
        saveDebounce.stop();
        root.composingNew = false;
        if (root.currentNoteId.length > 0)
            Notes.deleteNote(root.currentNoteId);
        root.currentNoteId = "";
        textInput.text = "";
        syncSelection();
    }

    function focusAtEnd() {
        if (!textInput)
            return;
        textInput.forceActiveFocus();
        const endPos = root.content.length;
        applySelection(endPos, endPos);
    }

    function applySelection(cursorPos, anchorPos) {
        if (!textInput)
            return;
        const textLength = root.content.length;
        const cursor = Math.max(0, Math.min(cursorPos, textLength));
        const anchor = Math.max(0, Math.min(anchorPos, textLength));
        textInput.select(anchor, cursor);
        if (cursor === anchor)
            textInput.deselect();
    }

    function scheduleCopylistUpdate(immediate = false) {
        if (!textInput)
            return;
        if (immediate) {
            copyListDebounce?.stop();
            updateCopyListEntries();
        } else {
            copyListDebounce.restart();
        }
    }

    function updateCopyListEntries() {
        if (!textInput)
            return;
        const textValue = root.content;
        if (!textValue || textValue.length === 0) {
            lastParsedCopylistText = "";
            parsedCopylistLines = [];
            root.copyListEntries = [];
            return;
        }

        if (textValue !== lastParsedCopylistText) {
            const lineRegex = /(.*?)(\r?\n|$)/g;
            let match = null;
            const parsed = [];
            while ((match = lineRegex.exec(textValue)) !== null) {
                const lineText = match[1];
                const newlineText = match[2];
                const lineStart = match.index;
                const lineEnd = lineStart + lineText.length;
                const bulletMatch = lineText.match(/^\s*-\s+(.*\S)\s*$/);
                if (bulletMatch) {
                    parsed.push({
                        content: bulletMatch[1].trim(),
                        start: lineStart,
                        end: lineEnd
                    });
                }
                if (newlineText === "")
                    break;
            }
            lastParsedCopylistText = textValue;
            parsedCopylistLines = parsed;
            if (parsed.length === 0) {
                root.copyListEntries = [];
                return;
            }
        }

        updateCopylistPositions();
    }

    function updateCopylistPositions() {
        if (!textInput || parsedCopylistLines.length === 0)
            return;
        const rawSelectionStart = textInput.selectionStart;
        const rawSelectionEnd = textInput.selectionEnd;
        const selectionStart = rawSelectionStart === -1 ? textInput.cursorPosition : rawSelectionStart;
        const selectionEnd = rawSelectionEnd === -1 ? textInput.cursorPosition : rawSelectionEnd;
        const rangeStart = Math.min(selectionStart, selectionEnd);
        const rangeEnd = Math.max(selectionStart, selectionEnd);

        const entries = parsedCopylistLines.map(line => {
            // Don't show copy button if line is (partially) selected
            const caretIntersects = rangeEnd > line.start && rangeStart <= line.end;
            if (caretIntersects)
                return null;
            const startRect = textInput.positionToRectangle(line.start);
            let endRect = textInput.positionToRectangle(line.end);
            if (!isFinite(startRect.y))
                return null;
            if (!isFinite(endRect.y))
                endRect = startRect;
            const lineBottom = endRect.y + endRect.height;
            const rectHeight = Math.max(lineBottom - startRect.y, textInput.font.pixelSize + 8);
            return {
                content: line.content,
                y: startRect.y,
                height: rectHeight
            };
        }).filter(entry => entry !== null);

        root.copyListEntries = entries;
    }

    implicitWidth: 300
    implicitHeight: 200

    Connections {
        target: Notes

        function onReadyChanged() {
            root.syncSelection();
        }

        // The desktop widget writes to the same store, so a note can appear,
        // change or vanish underneath this editor. Never overwrite what is
        // being typed here to follow it.
        function onListChanged() {
            root.syncSelection();
            if (textInput.activeFocus || saveDebounce.running)
                return;
            const note = Notes.noteById(root.currentNoteId);
            if (note && note.content !== root.content) {
                textInput.text = note.content;
                Qt.callLater(root.updateCopyListEntries);
            }
        }
    }

    ColumnLayout {
        id: contentItem
        anchors.fill: parent
        spacing: 0

        RowLayout {
            id: noteStrip
            Layout.fillWidth: true
            Layout.margins: Appearance.spacing.space150
            Layout.bottomMargin: 0
            spacing: Appearance.spacing.space100

            ListView {
                id: noteChips
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                orientation: ListView.Horizontal
                clip: true
                spacing: Appearance.spacing.space50
                model: Notes.list

                delegate: FilterChip {
                    id: noteChip
                    required property var modelData
                    label: root.notePreview(modelData.content)
                    toggled: !root.composingNew && modelData.id === root.currentNoteId
                    onClicked: root.selectNote(noteChip.modelData.id)
                }
            }

            RippleButton {
                id: addNoteButton
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: root.startNewNote()

                contentItem: MaterialSymbol {
                    verticalAlignment: Text.AlignVCenter
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "add"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }

                StyledToolTip {
                    text: Translation.tr("New note")
                }
            }

            RippleButton {
                id: deleteNoteButton
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                enabled: root.currentNoteId.length > 0
                onClicked: root.deleteCurrentNote()

                contentItem: MaterialSymbol {
                    verticalAlignment: Text.AlignVCenter
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "delete"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }

                StyledToolTip {
                    text: Translation.tr("Delete note")
                }
            }
        }

        ScrollView {
            id: editorScrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            onWidthChanged: root.scheduleCopylistUpdate(true)

            StyledTextArea { // This has to be a direct child of ScrollView for proper scrolling
                id: textInput
                anchors {
                    left: parent.left
                    right: parent.right
                }
                wrapMode: TextEdit.Wrap
                placeholderText: Translation.tr("Write something here...\nUse '-' to create copyable bullet points, like this:\n\nSheep fricker\n- 4x Slab\n- 1x Boat\n- 4x Redstone Dust\n- 1x Sticky Piston\n- 1x End Rod\n- 4x Redstone Repeater\n- 1x Redstone Torch\n- 1x Sheep")
                selectByMouse: true
                persistentSelection: true
                textFormat: TextEdit.PlainText
                background: null
                padding: Appearance.spacing.space300

                onTextChanged: {
                    if (textInput.activeFocus) {
                        saveDebounce.restart();
                    }
                    root.scheduleCopylistUpdate(true);
                }

                onHeightChanged: root.scheduleCopylistUpdate(true)
                onContentHeightChanged: root.scheduleCopylistUpdate(true)
                onCursorPositionChanged: root.scheduleCopylistUpdate()
                onSelectionStartChanged: root.scheduleCopylistUpdate()
                onSelectionEndChanged: root.scheduleCopylistUpdate()
            }

            Item {
                anchors.fill: parent
                visible: root.copyListEntries.length > 0
                clip: true

                Repeater {
                    model: ScriptModel {
                        values: root.copyListEntries
                    }
                    delegate: RippleButton {
                        id: copyButton
                        required property var modelData
                        readonly property real lineHeight: Math.min(Math.max(modelData.height, Appearance.font.pixelSize.normal + 6), root.maxCopyButtonSize)
                        readonly property real iconSizeLocal: Appearance.font.pixelSize.normal
                        readonly property real hitPadding: Appearance.spacing.space75
                        property bool justCopied: false

                        implicitHeight: lineHeight
                        implicitWidth: lineHeight
                        buttonRadius: height / 2
                        y: modelData.y
                        anchors.right: parent.right
                        anchors.rightMargin: Appearance.spacing.space150
                        z: 5

                        Timer {
                            id: resetState
                            interval: 700
                            onTriggered: {
                                copyButton.justCopied = false;
                            }
                        }

                        onClicked: {
                            Quickshell.clipboardText = copyButton.modelData.content;
                            justCopied = true;
                            resetState.start();
                        }

                        contentItem: Item {
                            anchors.centerIn: parent
                            MaterialSymbol {
                                id: iconItem
                                anchors.centerIn: parent
                                text: copyButton.justCopied ? "check" : "content_copy"
                                iconSize: copyButton.iconSizeLocal
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            id: statusLabel
            Layout.fillWidth: true
            Layout.margins: Appearance.spacing.space200
            horizontalAlignment: Text.AlignRight
            text: saveDebounce.running ? Translation.tr("Saving...") : Translation.tr("Saved    ")
            color: Appearance.colors.colSubtext
        }
    }

    Timer {
        id: saveDebounce
        interval: 500
        repeat: false
        onTriggered: saveContent()
    }

    Timer {
        id: copyListDebounce
        interval: 100
        repeat: false
        onTriggered: updateCopylistPositions()
    }
}
