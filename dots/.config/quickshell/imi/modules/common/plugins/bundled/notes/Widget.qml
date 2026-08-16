pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.plugins
import "../../designsystem/widgets" as Expressive

Item {
    id: root

    // Frost handling mirrors the other desktop widgets: the host PluginWidget
    // blurs the wallpaper region behind us, and the card below supplies the
    // tint on top. The region comes from that same card, so the widget cannot
    // disagree with its own surface about where the frost goes - the host's
    // fallback is `Appearance.rounding.large`, 7px tighter than the card's own
    // corner, which leaves blurred slivers outside all four of them.
    readonly property bool blurEnabled: PluginState.option("notes", "blurEnabled", false)
    readonly property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("notes")
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [card.blurRegion]

    // Set by the host while this widget is being dragged, and handed straight
    // to the card: the shadow lifts on hover and lifts further on a drag.
    property bool hostDragging: false
    // Set by the host while its own box is animating; the card drops its
    // shadow for the duration rather than re-blurring into a resizing FBO.
    property bool hostBoxInMotion: false

    // "list" | "edit". The card flips between the two rather than growing a
    // second surface - it is a 2x2 tile, there is no room for both.
    property string mode: "list"
    // The note being edited, or "" for one that does not exist yet.
    property string editingId: ""

    // A 2x2 component-grid tile (276x228 - cells are wider than tall). The host
    // (PluginWidget) sizes us from the manifest `grid` span and stretches this
    // root to fill it; the implicit size is only a fallback for standalone use.
    // See docs/widget-grid.md.
    implicitWidth: Appearance.sizes.widgetGridSpanX(2)
    implicitHeight: Appearance.sizes.widgetGridSpanY(2)
    anchors.fill: parent

    // The objectNames below are how NotesSurfacesRuntimeTest.qml finds these
    // controls to click them; ids are not reachable from outside the component.

    // Keyboard focus for the background layer surface is armed by the host
    // (PluginWidget hover + descendant focus), so this widget needs no per-field
    // OnDemand wiring - clicking the editor grabs Wayland keyboard focus.

    // A *content* tint, not the card's: the list well and the editor well are
    // surfaces drawn inside the card, and they thin with it so the frost reads
    // through the whole widget rather than through its edges only. Calendar is
    // the precedent, and `transparentize` rather than the card's `applyAlpha`
    // for the same reason it gives - colLayer2 already carries an alpha this
    // must scale rather than overwrite.
    readonly property color colSurface: root.blurEnabled
        ? ColorUtils.transparentize(Appearance.colors.colLayer2, 1 - root.backgroundOpacity)
        : Appearance.colors.colLayer1

    function openNewNote() {
        root.editingId = "";
        editArea.text = "";
        flipAnim.start();
    }

    function openNote(note) {
        root.editingId = note.id;
        editArea.text = note.content;
        flipAnim.start();
    }

    // One exit from edit mode, so an empty new note is never stored and an
    // emptied existing one is deleted rather than kept as a blank row.
    function saveAndBack() {
        const text = editArea.text;
        if (root.editingId.length === 0) {
            if (text.trim().length > 0)
                Notes.addNote(text);
        } else if (text.trim().length === 0) {
            Notes.deleteNote(root.editingId);
        } else {
            Notes.updateNote(root.editingId, text);
        }
        root.editingId = "";
        flipAnim.start();
    }

    // The surface every other desktop widget already composes. It owns the
    // tint pair, the rounding (this widget's own `verylarge` was the same 30
    // spelled twice), the frost record above, and the drop shadow with its
    // hover and drag lift - which is what this widget had none of while the
    // root Rectangle painted the card's surface over the top of it.
    //
    // No `tensionX`/`tensionY`: the manifest offers one span, so the host
    // draws no resize grip here and there is never a bow to render.
    Expressive.WidgetCard {
        id: card
        anchors.fill: parent
        tint: Appearance.colors.colSecondaryContainer
        useBlurBackground: root.blurEnabled
        backgroundOpacity: root.backgroundOpacity
        dragging: root.hostDragging
        hostMotionActive: root.hostBoxInMotion

        Item {
            id: cardWrapper
            anchors.fill: parent

            transform: Scale {
                id: flipScale
                origin.x: cardWrapper.width / 2
                origin.y: cardWrapper.height / 2
                xScale: 1
            }

            SequentialAnimation {
                id: flipAnim
                NumberAnimation {
                    target: flipScale
                    property: "xScale"
                    to: 0
                    duration: Appearance.animation.elementMoveFaster.duration
                    easing.type: Easing.InQuad
                }
                ScriptAction {
                    script: root.mode = (root.mode === "list" ? "edit" : "list")
                }
                NumberAnimation {
                    target: flipScale
                    property: "xScale"
                    to: 1
                    duration: Appearance.animation.elementMoveFaster.duration
                    easing.type: Easing.OutQuad
                }
            }

            ColumnLayout {
                id: listPage
                anchors.fill: parent
                anchors.margins: Appearance.spacing.space200
                spacing: Appearance.spacing.space150
                visible: root.mode === "list"

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

                    ToolbarPairedFab {
                        id: addNoteButton
                        objectName: "addNoteButton"
                        Layout.alignment: Qt.AlignVCenter
                        baseSize: 34
                        iconText: "add"
                        onClicked: root.openNewNote()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: root.colSurface

                    StyledText {
                        anchors.centerIn: parent
                        visible: Notes.list.length === 0
                        text: Translation.tr("No notes yet")
                        color: Appearance.colors.colSubtext
                    }

                    StyledListView {
                        id: notesList
                        objectName: "notesList"
                        anchors.fill: parent
                        anchors.margins: Appearance.spacing.space100
                        clip: true
                        spacing: Appearance.spacing.space75
                        model: Notes.list

                        delegate: Rectangle {
                            id: noteRow
                            required property var modelData

                            width: notesList.width
                            implicitHeight: 40
                            radius: Appearance.rounding.small
                            color: noteRowArea.containsMouse
                                ? Appearance.colors.colLayer2Hover
                                : Appearance.colors.colLayer2

                            MouseArea {
                                id: noteRowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openNote(noteRow.modelData)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Appearance.spacing.space125
                                anchors.rightMargin: Appearance.spacing.space50
                                spacing: Appearance.spacing.space50

                                StyledText {
                                    Layout.fillWidth: true
                                    // A note's body is user content read off disk;
                                    // StyledText is a bare Text and would render
                                    // markup in it without this.
                                    textFormat: Text.PlainText
                                    text: noteRow.modelData.content
                                    color: Appearance.colors.colOnLayer2
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                RippleButton {
                                    id: deleteNoteButton
                                    objectName: "deleteNoteButton"
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    buttonRadius: Appearance.rounding.full
                                    onClicked: Notes.deleteNote(noteRow.modelData.id)

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "delete"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: editPage
                anchors.fill: parent
                anchors.margins: Appearance.spacing.space200
                spacing: Appearance.spacing.space150
                visible: root.mode === "edit"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space100

                    RippleButton {
                        id: backButton
                        implicitWidth: 30
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        onClicked: root.saveAndBack()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "arrow_back"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.editingId.length === 0 ? Translation.tr("New note") : Translation.tr("Edit note")
                        font.family: Appearance.font.family.expressive
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    ToolbarPairedFab {
                        id: saveNoteButton
                        objectName: "saveNoteButton"
                        Layout.alignment: Qt.AlignVCenter
                        baseSize: 34
                        iconText: "save"
                        onClicked: root.saveAndBack()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: root.colSurface

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: Appearance.spacing.space100
                        clip: true

                        StyledTextArea {
                            id: editArea
                            objectName: "editArea"
                            background: null
                            wrapMode: TextEdit.Wrap
                            // Same reason as the list row: never interpret a note's
                            // own text as markup.
                            textFormat: TextEdit.PlainText
                            placeholderText: Translation.tr("Jot a note…")
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }
    }
}
