import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    // The local file's two tabs, then one tab per Google task list while the
    // account offers them: the source picker rides the tab bar it already
    // has (BottomWidgetGroup's height is a fixed budget; a row of its own
    // took 40px out of the list). The lists never merge (the local file has
    // no ids).
    readonly property var localTabs: [{"icon": "checklist", "name": Translation.tr("Unfinished")}, {"name": Translation.tr("Done"), "icon": "check_circle"}]
    readonly property bool googleAvailable: GoogleTasks.enabled && GoogleTasks.lists.length > 0
    readonly property var googleLists: root.googleAvailable ? GoogleTasks.lists : []
    readonly property var tabButtonList: root.localTabs.concat(root.googleLists.map(l => ({ "icon": "cloud", "name": l.title, "listId": l.id })))
    readonly property bool googleSource: tabBar.currentIndex >= root.localTabs.length
    // The chosen Google list is an ID, never the tab's index: the lists are
    // refetched and can be added, removed or reordered under a standing
    // index, which would silently show a different list. The index is
    // derived from the id and falls back to the local tabs when it is gone.
    property string selectedListId: ""
    readonly property string currentGoogleListId: root.googleSource ? (root.tabButtonList[tabBar.currentIndex]?.listId ?? "") : ""
    onCurrentGoogleListIdChanged: {
        if (root.currentGoogleListId.length > 0) {
            root.selectedListId = root.currentGoogleListId;
            GoogleTasks.selectList(root.currentGoogleListId);
        } else if (root.googleSource === false) {
            root.selectedListId = "";
        }
    }
    onTabButtonListChanged: {
        if (root.selectedListId.length === 0) return;
        const at = root.tabButtonList.findIndex(tab => tab.listId === root.selectedListId);
        if (at === -1) { root.selectedListId = ""; tabBar.setCurrentIndex(0); }
        else if (tabBar.currentIndex !== at) tabBar.setCurrentIndex(at);
    }
    onGoogleAvailableChanged: if (!googleAvailable && root.googleSource) tabBar.setCurrentIndex(0)
    property bool showAddDialog: false
    property int dialogMargins: Appearance.spacing.space250
    property int fabSize: 48
    property int fabMargins: Appearance.spacing.space175

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                tabBar.incrementCurrentIndex();
            } else if (event.key === Qt.Key_PageUp) {
                tabBar.decrementCurrentIndex();
            }
            event.accepted = true;
        }
        // Open add dialog on "N" (any modifiers)
        else if (event.key === Qt.Key_N) {
            root.showAddDialog = true
            event.accepted = true;
        }
        // Close dialog on Esc if open
        else if (event.key === Qt.Key_Escape && root.showAddDialog) {
            root.showAddDialog = false
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SecondaryTabBar {
            id: tabBar
            currentIndex: swipeView.currentIndex

            Repeater {
                model: root.tabButtonList
                delegate: SecondaryTabButton {
                    buttonText: modelData.name
                    buttonIcon: modelData.icon
                }
            }
        }

        SwipeView {
            id: swipeView
            Layout.topMargin: Appearance.spacing.space150
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Appearance.spacing.space150
            clip: true
            currentIndex: tabBar.currentIndex

            // To Do tab
            // The filters pass Todo.list's own objects through untouched:
            // TaskList's ScriptModel diffs by identity, so wrapping each item in
            // a fresh object per update (the old Object.assign originalIndex
            // annotation) made every change read as remove-all + add-all and no
            // list transition could ever fire. Indices are resolved at click
            // time in TaskList instead.
            TaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "check_circle"
                emptyPlaceholderText: Translation.tr("Nothing here!")
                taskList: Todo.list.filter(function(item) { return !item.done; })
            }
            TaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "checklist"
                emptyPlaceholderText: Translation.tr("Finished tasks will go here")
                taskList: Todo.list.filter(function(item) { return item.done; })
            }
            // One page per Google list: its open tasks (Google keeps the
            // completed ones itself).
            Repeater {
                model: root.googleLists
                TaskList {
                    required property var modelData
                    listBottomPadding: root.fabSize + root.fabMargins * 2
                    emptyPlaceholderIcon: "cloud_done"
                    emptyPlaceholderText: Translation.tr("Nothing open in %1").arg(modelData.title)
                    source: "google"
                    taskList: GoogleTasks.currentListId === modelData.id ? GoogleTasks.tasks : []
                }
            }

        }
    }

    // + FAB
    StyledRectangularShadow {
        target: fabButton
        radius: fabButton.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }
    FloatingActionButton {
        id: fabButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins

        onClicked: root.showAddDialog = true
        iconText: "add"
    }

    Item {
        anchors.fill: parent
        z: 9999

        visible: opacity > 0
        opacity: root.showAddDialog ? 1 : 0
        Behavior on opacity {
            NumberAnimation { 
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        onVisibleChanged: {
            if (!visible) {
                todoInput.text = ""
                fabButton.focus = true
            }
        }

        Rectangle { // Scrim
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                preventStealing: true
                propagateComposedEvents: false
            }
        }

        Rectangle { // The dialog
            id: dialog
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.dialogMargins
            implicitHeight: dialogColumnLayout.implicitHeight

            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal

            function addTask() {
                if (todoInput.text.length > 0) {
                    if (root.googleSource)
                        GoogleTasks.addTask(todoInput.text)
                    else
                        Todo.addTask(todoInput.text)
                    todoInput.text = ""
                    root.showAddDialog = false
                    if (!root.googleSource)
                        tabBar.setCurrentIndex(0) // Show unfinished tasks
                }
            }

            ColumnLayout {
                id: dialogColumnLayout
                anchors.fill: parent
                spacing: Appearance.spacing.space200

                StyledText {
                    Layout.topMargin: Appearance.spacing.space200
                    Layout.leftMargin: Appearance.spacing.space200
                    Layout.rightMargin: Appearance.spacing.space200
                    Layout.alignment: Qt.AlignLeft
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: Translation.tr("Add task")
                }

                TextField {
                    id: todoInput
                    Layout.fillWidth: true
                    Layout.leftMargin: Appearance.spacing.space200
                    Layout.rightMargin: Appearance.spacing.space200
                    padding: Appearance.spacing.space150
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    renderType: Text.NativeRendering
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    placeholderText: Translation.tr("Task description")
                    placeholderTextColor: Appearance.m3colors.m3outline
                    focus: root.showAddDialog
                    onAccepted: dialog.addTask()

                    background: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.verysmall
                        border.width: Appearance.borderWidth.emphasis
                        border.color: todoInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        color: "transparent"
                    }

                    cursorDelegate: Rectangle {
                        width: 1
                        color: todoInput.activeFocus ? Appearance.colors.colPrimary : "transparent"
                        radius: 1
                    }
                }

                RowLayout {
                    Layout.bottomMargin: Appearance.spacing.space200
                    Layout.leftMargin: Appearance.spacing.space200
                    Layout.rightMargin: Appearance.spacing.space200
                    Layout.alignment: Qt.AlignRight
                    spacing: Appearance.spacing.space100

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.showAddDialog = false
                    }
                    DialogButton {
                        buttonText: Translation.tr("Add")
                        enabled: todoInput.text.length > 0
                        onClicked: dialog.addTask()
                    }
                }
            }
        }
    }
}
