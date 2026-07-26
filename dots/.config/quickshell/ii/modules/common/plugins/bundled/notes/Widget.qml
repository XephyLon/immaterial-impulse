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

    // A square 2x2 desktop-grid component.
    implicitWidth: 228
    implicitHeight: 228
    width: implicitWidth
    height: implicitHeight
    radius: Appearance.rounding.verylarge
    // Matugen-tinted card (secondary container) instead of a neutral surface.
    color: root.blurEnabled
        ? ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 1 - root.backgroundOpacity)
        : Appearance.colors.colSecondaryContainer
    border.width: 0

    // Keyboard focus for the background layer surface is armed by the host
    // (PluginWidget hover + descendant focus), so this widget needs no per-field
    // OnDemand wiring - clicking the editor grabs Wayland keyboard focus.

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space200
        spacing: Appearance.spacing.space150

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            MaterialShapeWrappedMaterialSymbol {
                shape: MaterialShape.Shape.Clover
                text: "sticky_note_2"
                iconSize: Appearance.font.pixelSize.large
                implicitSize: 36
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Notes")
                font.family: Appearance.font.family.expressive
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        // Distinct rounded editing surface so the note area reads as a card
        // within the widget, not bare text on the background.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: root.blurEnabled
                ? ColorUtils.transparentize(Appearance.colors.colLayer2, 1 - root.backgroundOpacity)
                : Appearance.colors.colLayer1

            ScrollView {
                anchors.fill: parent
                anchors.margins: Appearance.spacing.space100
                clip: true

                StyledTextArea {
                    id: noteArea
                    background: null
                    wrapMode: TextEdit.Wrap
                    placeholderText: Translation.tr("Jot a note…")
                    color: Appearance.colors.colOnLayer1
                    onTextChanged: if (root.ready) saveDebounce.restart()
                }
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
