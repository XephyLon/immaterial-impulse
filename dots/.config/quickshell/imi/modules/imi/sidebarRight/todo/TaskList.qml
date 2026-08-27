import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var taskList
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText
    property int todoListItemSpacing: Appearance.spacing.space50
    property int todoListItemPadding: Appearance.spacing.space100
    property int listBottomPadding: 80

    StyledListView {
        id: listView
        anchors.fill: parent
        spacing: root.todoListItemSpacing
        // animateAppearance stays at the view's default (on): a task marked done
        // slides out and the rows below close the gap, instead of the list
        // hard-cutting to its new shape. That only works because taskList holds
        // the same objects Todo.list does - ScriptModel diffs by identity, so a
        // per-update wrapper would read as remove-all + add-all and fly the
        // whole list in on every change.
        model: ScriptModel {
            values: root.taskList
        }
        delegate: Item {
            id: todoItem
            required property var modelData
            property bool pendingDoneToggle: false
            property bool pendingDelete: false
            property bool enableHeightAnimation: false

            // Resolved at click time - a stored index goes stale across
            // deletes. Identity first: on current quickshell, ScriptModel
            // hands the delegate the very object Todo.list holds. But that
            // is a property of the PIN, not of QML - before quickshell
            // a611932 ("core/scriptmodel: represent members as a
            // QJSValueList") the model stored QVariants and every delegate
            // saw a fresh copy, so indexOf answered -1 and each done/delete
            // click was a silent no-op (the Gentoo ebuild pins exactly such
            // a commit). The content fallback covers those installs; equal
            // payloads are interchangeable, so a duplicate task resolving to
            // its twin commits the same edit.
            function resolveIndex(): int {
                const md = todoItem.modelData;
                const idx = Todo.list.indexOf(md);
                if (idx !== -1)
                    return idx;
                return Todo.list.findIndex(task =>
                    task.content === md.content && task.done === md.done);
            }

            implicitHeight: todoItemRectangle.implicitHeight
            width: ListView.view.width
            clip: true

            Behavior on implicitHeight {
                enabled: enableHeightAnimation
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Rectangle {
                id: todoItemRectangle
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: todoContentRowLayout.implicitHeight
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.small

                ColumnLayout {
                    id: todoContentRowLayout
                    anchors.left: parent.left
                    anchors.right: parent.right

                    StyledText {
                        id: todoContentText
                        Layout.fillWidth: true // Needed for wrapping
                        Layout.leftMargin: Appearance.spacing.space150
                        Layout.rightMargin: Appearance.spacing.space150
                        Layout.topMargin: todoListItemPadding
                        text: todoItem.modelData.content
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        Layout.leftMargin: Appearance.spacing.space150
                        Layout.rightMargin: Appearance.spacing.space150
                        Layout.bottomMargin: todoListItemPadding
                        Item {
                            Layout.fillWidth: true
                        }
                        TodoItemActionButton {
                            Layout.fillWidth: false
                            onClicked: {
                                const index = todoItem.resolveIndex();
                                if (index === -1)
                                    return;
                                if (!todoItem.modelData.done)
                                    Todo.markDone(index);
                                else
                                    Todo.markUnfinished(index);
                            }
                            contentItem: MaterialSymbol {
                                verticalAlignment: Text.AlignVCenter
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: todoItem.modelData.done ? "remove_done" : "check"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        TodoItemActionButton {
                            Layout.fillWidth: false
                            onClicked: {
                                const index = todoItem.resolveIndex();
                                if (index !== -1)
                                    Todo.deleteItem(index);
                            }
                            contentItem: MaterialSymbol {
                                verticalAlignment: Text.AlignVCenter
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "delete_forever"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        // Placeholder when list is empty
        visible: opacity > 0
        opacity: taskList.length === 0 ? 1 : 0
        anchors.fill: parent

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 55
                color: Appearance.m3colors.m3outline
                text: emptyPlaceholderIcon
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3outline
                horizontalAlignment: Text.AlignHCenter
                text: emptyPlaceholderText
            }
        }
    }
}
