import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../services/ai/ai_sessions.js" as Sessions
import QtQuick
import QtQuick.Layouts

/**
 * The sessions view (spec 2026-08-31): every auto-saved chat, pinned first
 * then most recent, with open/rename/pin/delete on the row - the fork's
 * SessionList grammar on imi tokens - and the un-imported legacy flat
 * files at the foot. Hosted by AiChat's view switcher; the back arrow and
 * the history chip both leave.
 */
Rectangle {
    id: root
    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.large

    signal closed()

    // Arrives from the right, the switcher's going-deeper direction.
    transform: Translate { id: slideIn }
    Component.onCompleted: {
        slideIn.x = 24;
        slideAnim.start();
        if (!AiSessions.loaded) AiSessions.rebuild();
    }
    NumberAnimation {
        id: slideAnim
        target: slideIn
        property: "x"
        to: 0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Easing.OutExpo
    }

    // The rows re-label ("5m" -> "6m") while the view is open; a minute is
    // the label's own resolution.
    property real nowMs: Date.now()
    Timer {
        interval: 60000
        running: root.visible
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    // Legacy flat files offered for import at the foot; lastSession was the
    // retired write-only autosave and is not worth a row.
    readonly property var legacyChats: Ai.savedChats
        .map(path => ({ path: path, name: path.split("/").pop().replace(".json", "") }))
        .filter(entry => entry.name !== "lastSession" && entry.name !== "sessions")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space150
        spacing: Appearance.spacing.space100

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.closed()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
            }
            StyledText {
                text: Translation.tr("Chats")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
        }

        StyledText {
            visible: AiSessions.index.length === 0 && root.legacyChats.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            Layout.topMargin: Appearance.spacing.space400
            text: Translation.tr("Nothing here yet - chats save themselves as you talk.")
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: sessionColumn.implicitHeight

            ColumnLayout {
                id: sessionColumn
                width: parent.width
                spacing: Appearance.spacing.space25

                Repeater {
                    model: AiSessions.index
                    delegate: SessionRow {}
                }

                StyledText {
                    visible: root.legacyChats.length > 0
                    Layout.topMargin: Appearance.spacing.space200
                    text: Translation.tr("Legacy saved chats")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                Repeater {
                    model: root.legacyChats
                    delegate: RippleButton {
                        id: legacyRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.normal
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: {
                            AiSessions.importLegacy(legacyRow.modelData.path);
                            root.closed();
                        }
                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Appearance.spacing.space100
                            anchors.rightMargin: Appearance.spacing.space100
                            spacing: Appearance.spacing.space100
                            MaterialSymbol {
                                text: "history"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: legacyRow.modelData.name
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            StyledText {
                                text: Translation.tr("import")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                    }
                }
            }
        }
    }

    component RowAction: RippleButton {
        id: actionButton
        property string glyph: ""
        property real glyphFill: 0
        implicitWidth: 28
        implicitHeight: 28
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colRipple: Appearance.colors.colLayer2Active
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: actionButton.glyph
            fill: actionButton.glyphFill
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer1
        }
    }

    component SessionRow: Rectangle {
        id: row
        required property var modelData
        readonly property bool current: row.modelData.id === AiSessions.currentId
        property bool renaming: false

        Layout.fillWidth: true
        implicitHeight: 48
        radius: Appearance.rounding.normal
        color: row.current ? Appearance.colors.colSecondaryContainer
             : rowHover.hovered ? Appearance.colors.colLayer2Hover : "transparent"
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        HoverHandler { id: rowHover }
        MouseArea {
            anchors.fill: parent
            enabled: !row.renaming
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                AiSessions.openSession(row.modelData.id);
                root.closed();
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Appearance.spacing.space150
            anchors.rightMargin: Appearance.spacing.space100
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                visible: row.modelData.pinned
                text: "keep"
                fill: 1
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            // ONE text element for the title: readOnly until the rename
            // action arms it (the InlineEditChip rule - no label/input
            // twins).
            TextInput {
                id: titleInput
                Layout.fillWidth: true
                readOnly: !row.renaming
                // autoScroll chases the cursor, which sits at the END when
                // the bound text lands - hovered rows showed their tails
                // ("ently working on…"). At rest the head is the title.
                autoScroll: row.renaming
                // A readOnly TextInput still TAKES clicks (cursor and
                // selection handling), so a click on the title never
                // reached the row's open area - only clicks beside the
                // text opened the chat. Disabled outside a rename, the
                // whole row is one target.
                enabled: row.renaming
                text: row.modelData.title.length > 0 ? row.modelData.title
                                                     : Translation.tr("Untitled chat")
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.small
                color: row.current ? Appearance.colors.colOnSecondaryContainer
                                   : Appearance.colors.colOnLayer1
                clip: true
                selectionColor: Appearance.colors.colPrimary
                selectedTextColor: Appearance.m3colors.m3onPrimary
                function finish(commit) {
                    if (!row.renaming) return;
                    row.renaming = false;
                    if (commit && text.trim().length > 0)
                        AiSessions.rename(row.modelData.id, text.trim());
                    else
                        text = Qt.binding(() => row.modelData.title.length > 0
                            ? row.modelData.title : Translation.tr("Untitled chat"));
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        titleInput.finish(true); event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        titleInput.finish(false); event.accepted = true;
                    }
                }
                onActiveFocusChanged: if (!activeFocus) titleInput.finish(false)
            }

            StyledText {
                // The hover actions take this label's room; both at once
                // crushed the title.
                visible: !row.renaming && !rowHover.hovered
                text: Sessions.agoLabel(root.nowMs, row.modelData.updatedAt)
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            RowAction {
                visible: rowHover.hovered && !row.renaming
                glyph: row.modelData.pinned ? "keep_off" : "keep"
                onClicked: AiSessions.setPinned(row.modelData.id, !row.modelData.pinned)
            }
            RowAction {
                visible: rowHover.hovered && !row.renaming
                glyph: "edit"
                onClicked: {
                    row.renaming = true;
                    titleInput.text = row.modelData.title;
                    titleInput.forceActiveFocus();
                    titleInput.selectAll();
                }
            }
            RowAction {
                visible: rowHover.hovered && !row.renaming
                glyph: "delete"
                onClicked: AiSessions.remove(row.modelData.id)
            }
        }
    }
}
