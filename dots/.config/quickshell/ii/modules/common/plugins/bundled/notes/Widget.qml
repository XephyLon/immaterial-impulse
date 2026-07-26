pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.plugins

Rectangle {
    id: root

    // Frost handling mirrors the other desktop widgets: the host PluginWidget
    // blurs the wallpaper region behind us, and this card supplies the tint on
    // top. With no custom blurRegions the host frosts the whole card.
    readonly property bool blurEnabled: PluginState.option("notes", "blurEnabled", false)
    readonly property real backgroundOpacity: Config.options.plugins.blurOpacity
    readonly property bool managesBlurTint: true

    // True once the persisted note has been read. Guards the text-change hook so
    // assigning the loaded content does not schedule a redundant save.
    property bool ready: false

    implicitWidth: 320
    implicitHeight: 260
    width: implicitWidth
    height: implicitHeight
    radius: Appearance.rounding.verylarge
    color: root.blurEnabled
        ? ColorUtils.transparentize(Appearance.colors.colLayer1, 1 - root.backgroundOpacity)
        : Appearance.colors.colLayer0
    border.width: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space200
        spacing: Appearance.spacing.space100

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                text: "sticky_note_2"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Notes")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            StyledTextArea {
                id: noteArea
                wrapMode: TextEdit.Wrap
                placeholderText: Translation.tr("Notes…")
                onTextChanged: if (root.ready) saveDebounce.restart()
            }
        }
    }

    // Debounced autosave: coalesce rapid edits into one write ~500ms after the
    // last keystroke, matching the overlay notes editor.
    Timer {
        id: saveDebounce
        interval: 500
        repeat: false
        onTriggered: noteFile.setText(noteArea.text)
    }

    // Single persistent scratchpad shared with the overlay notes editor. Reloads
    // on external change, but never overwrites text while the user is typing here.
    FileView {
        id: noteFile
        path: Qt.resolvedUrl(Directories.notesPath)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (!noteArea.activeFocus && noteArea.text !== noteFile.text())
                noteArea.text = noteFile.text();
            root.ready = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                noteFile.setText("");
            } else {
                console.log("[Notes] Error loading file: " + error);
            }
            root.ready = true;
        }
    }
}
