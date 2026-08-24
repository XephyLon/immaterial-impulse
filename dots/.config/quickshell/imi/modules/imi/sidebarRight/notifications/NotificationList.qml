import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    NotificationListView { // Scrollable window
        id: listview
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: statusRow.top
        anchors.bottomMargin: Appearance.spacing.space100

        clip: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: listview.width
                height: listview.height
                radius: Appearance.rounding.normal
            }
        }

        popup: false
    }

    // Placeholder when list is empty. Given the list's area rather than the
    // whole column: the status row along the bottom is not space the empty
    // state can use, and the placeholder decides whether its shape fits from
    // the height it is handed.
    Item {
        anchors.fill: listview

        PagePlaceholder {
            // This list shares the sidebar column with a bottom widget group of
            // fixed height (see BottomWidgetGroup.expandedHeight), so on a short
            // screen it is squeezed until the shape reaches past the top of the
            // rounded container holding it - which does not clip (#87).
            dropIconWhenCramped: true
            shown: Notifications.list.length === 0
            icon: "notifications_active"
            description: Translation.tr("Nothing")
            shape: MaterialShape.Shape.Ghostish
            descriptionHorizontalAlignment: Text.AlignHCenter
        }
    }

    // The status bar's entrance is the fork's converging halves: the snooze
    // icon slides in from the left, the clear icon from the right, the count
    // fading between them, after the fork's own deliberate 250ms beat. The
    // buttons are GroupButtons, whose opacity and transform are free
    // channels (no interaction model, no dim) - the same reading that lets
    // the toggle tiles be dressed.
    property int entranceTrigger: -1
    property real _convergeLeft: 0
    property real _convergeRight: 0
    property real _statusOpacity: 1
    onEntranceTriggerChanged: {
        statusConverge.stop();
        root._convergeLeft = -40;
        root._convergeRight = 40;
        root._statusOpacity = 0;
        statusConverge.start();
    }
    SequentialAnimation {
        id: statusConverge
        PauseAnimation { duration: Appearance.animation.scale(250) }
        ParallelAnimation {
            NumberAnimation { target: root; property: "_statusOpacity"; from: 0; to: 1; duration: Appearance.animation.scale(320); easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "_convergeLeft"; from: -40; to: 0; duration: Appearance.animation.scale(350); easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "_convergeRight"; from: 40; to: 0; duration: Appearance.animation.scale(350); easing.type: Easing.OutCubic }
        }
    }

    ButtonGroup {
        id: statusRow
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        NotificationStatusButton {
            Layout.fillWidth: false
            buttonIcon: "notifications_paused"
            toggled: Notifications.silent
            opacity: root._statusOpacity
            transform: Translate { x: root._convergeLeft }
            onClicked: () => {
                Notifications.silent = !Notifications.silent;
            }
        }
        NotificationStatusButton {
            enabled: false
            Layout.fillWidth: true
            opacity: root._statusOpacity
            buttonText: Translation.tr("%1 notifications").arg(Notifications.list.length)
        }
        NotificationStatusButton {
            Layout.fillWidth: false
            buttonIcon: "delete_sweep"
            opacity: root._statusOpacity
            transform: Translate { x: root._convergeRight }
            onClicked: () => {
                Notifications.discardAllNotifications()
            }
        }
    }
}