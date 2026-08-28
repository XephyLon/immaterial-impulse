import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The phone's mirrored notifications, grouped by the app that posted them.
 *
 * The shape is the shell's own notification card
 * (modules/common/widgets/NotificationGroup.qml) rather than a second look
 * invented for the phone: one card per app, the newest on top, right-click
 * or the chevron expands the group, a drag past the threshold dismisses it,
 * and each notification carries a chip row - Close, whatever actions the
 * daemon relayed, an inline reply where the app offers one, and Copy.
 *
 * It is not that COMPONENT, because that one is written against
 * services/Notifications.qml's model end to end: its rows carry a
 * `notificationId` the freedesktop server minted, dismissal goes through
 * Notifications.discardNotification, and its popup half owns a timeout this
 * list has no equivalent of. A phone notification is a PUBLIC id on a KDE
 * Connect leaf, dismissed on that leaf, with a `replyId` and a list of
 * Android action keys instead. Teaching one card both models would put a
 * branch on every line of it.
 *
 * The delegates are declared in place rather than as inline components: an
 * inline component gets a scope of its own, so it could reach neither the
 * list view whose drag state the swipe leans on nor the card the row
 * belongs to.
 *
 * The empty state says WHY there is nothing, down to the missing busctl,
 * because "No notifications" over a dead daemon is a lie the user cannot
 * see through.
 */
Item {
    id: root

    property real appear: 1

    readonly property int count: PhoneNotifications.count
    // Which of the four reasons there is nothing to draw, most specific
    // first. The phone-side one is last because it is the only one that
    // means the link itself is fine.
    readonly property string emptyTitle: {
        if (!PhoneConnect.installed) return Translation.tr("busctl was not found");
        if (!PhoneConnect.available) return Translation.tr("No phone daemon is running");
        if (PhoneConnect.devices.length === 0) return Translation.tr("No devices yet");
        return Translation.tr("No notifications");
    }
    readonly property string emptyDescription: {
        if (!PhoneConnect.installed) return Translation.tr("Phone Connect drives KDE Connect and Valent over D-Bus through busctl, which ships with systemd.");
        if (!PhoneConnect.available) return Translation.tr("Start KDE Connect or Valent to see your phone here.");
        if (PhoneConnect.devices.length === 0) return Translation.tr("Pair your phone from KDE Connect or Valent and it will appear here.");
        return Translation.tr("Make sure KDE Connect has Notification Access on your phone.");
    }

    PagePlaceholder {
        shown: root.count === 0
        dropIconWhenCramped: true
        icon: PhoneConnect.devices.length === 0 ? "mobile_off" : "notifications_off"
        shape: MaterialShape.Shape.Ghostish
        title: root.emptyTitle
        description: root.emptyDescription
        descriptionHorizontalAlignment: Text.AlignHCenter
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        visible: root.count > 0
        clip: true
        spacing: Appearance.spacing.space100

        model: ScriptModel {
            values: PhoneNotifications.appNameList
        }

        // ---- one app's notifications, as one card ----------------------
        delegate: MouseArea {
            id: card
            required property int index
            required property var modelData

            readonly property string appName: card.modelData
            property bool expanded: false
            readonly property var group: PhoneNotifications.groupsByAppName[card.appName] ?? null
            // Newest first, the way the shell's own group draws them.
            readonly property var notifications: (card.group?.notifications ?? []).slice().reverse()
            readonly property int notificationCount: card.notifications.length
            // KDE Connect saves the posting app's icon to a file and hands
            // the absolute PATH over as `iconPath` (the group carries the
            // first one, the same derivation services/Notifications.qml uses
            // for a desktop group). NotificationAppIcon takes a URL, so it is
            // spelled the way every other file source in this tree is; a
            // notification that arrived without one leaves it empty and the
            // widget draws its glyph instead.
            readonly property string appIconPath: FileUtils.trimFileProtocol(card.group?.appIcon ?? "")
            readonly property string appIconUrl: card.appIconPath.length === 0 ? ""
                : "file://" + card.appIconPath.split("/").map(encodeURIComponent).join("/")

            readonly property real dragConfirmThreshold: 70
            readonly property real dismissOvershoot: 20
            // The neighbours lean with the card being dragged, which is what
            // makes a swipe read as one gesture on a stack rather than as
            // one card sliding out of a list that stands still.
            readonly property real indexDiff: Math.abs(listView.dragIndex - card.index)
            readonly property real xOffset: card.indexDiff === 0 ? listView.dragDistance
                : Math.abs(listView.dragDistance) > card.dragConfirmThreshold ? 0
                : card.indexDiff === 1 ? (listView.dragDistance * 0.3)
                : card.indexDiff === 2 ? (listView.dragDistance * 0.1) : 0

            width: listView.width
            implicitHeight: background.implicitHeight
            hoverEnabled: true

            function dismissWithAnimation(left: bool): void {
                listView.resetDrag();
                background.anchors.leftMargin = background.anchors.leftMargin; // break the binding
                dismissAnimation.left = left;
                dismissAnimation.running = true;
            }

            SequentialAnimation {
                id: dismissAnimation
                property bool left: true
                running: false

                NumberAnimation {
                    target: background.anchors
                    property: "leftMargin"
                    to: (card.width + card.dismissOvershoot) * (dismissAnimation.left ? -1 : 1)
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
                // Closes over plain data and a singleton, never over the
                // delegate: the swipe's whole point is that this card is
                // leaving, and the model refetch that follows destroys it -
                // a closure holding `card` would run against a dead object.
                onFinished: {
                    const ids = card.notifications.map(n => n.publicId);
                    Qt.callLater(() => {
                        for (const id of ids)
                            PhoneNotifications.dismiss(id);
                    });
                }
            }

            DragManager {
                id: dragManager
                anchors.fill: parent
                interactive: !card.expanded
                automaticallyReset: false
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton)
                        card.expanded = !card.expanded;
                }
                onDraggingChanged: {
                    if (dragManager.dragging)
                        listView.dragIndex = card.index;
                }
                onDragDiffXChanged: listView.dragDistance = dragManager.dragDiffX
                onDragReleased: (diffX, diffY) => {
                    if (Math.abs(diffX) > card.dragConfirmThreshold)
                        card.dismissWithAnimation(diffX < 0);
                    else
                        dragManager.resetDrag();
                }
            }

            Rectangle {
                id: background
                anchors.left: parent.left
                anchors.leftMargin: card.xOffset
                width: parent.width
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                clip: true
                implicitHeight: cardColumn.implicitHeight + Appearance.spacing.space150 * 2

                Behavior on anchors.leftMargin {
                    enabled: !dragManager.dragging
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                ColumnLayout {
                    id: cardColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Appearance.spacing.space150
                    spacing: Appearance.spacing.space100

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space100

                        // The shell's own notification icon, on this model's
                        // fields: `image` is the picture slot - a URL to a
                        // file - and the glyph guessed from the title is what
                        // it falls back to when the phone sent no icon. No
                        // second resolution scheme, and no `appIcon`: that
                        // slot goes through the icon THEME, which knows
                        // nothing about a path kdeconnectd wrote.
                        NotificationAppIcon {
                            Layout.alignment: Qt.AlignVCenter
                            implicitSize: Appearance.font.pixelSize.huge + Appearance.spacing.space100
                            image: card.appIconUrl
                            summary: card.notifications[0]?.title ?? card.appName
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            // An app's name comes off the phone; never markup.
                            textFormat: Text.PlainText
                            text: card.appName
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: NotificationUtils.getFriendlyNotifTimeString(card.group?.time ?? 0)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        NotificationGroupExpandButton {
                            // Only where there is a second notification to
                            // reveal. `NotificationGroup` gates its own on
                            // `multipleNotifications: notificationCount > 1`
                            // and this copy did not, so a group of one drew an
                            // affordance that expanded nothing.
                            visible: card.notificationCount > 1
                            count: card.notificationCount
                            expanded: card.expanded
                            onClicked: card.expanded = !card.expanded
                            altAction: () => { card.expanded = !card.expanded }

                            StyledToolTip {
                                text: Translation.tr("Tip: right-clicking a group\nalso expands it")
                            }
                        }
                    }

                    // ---- one notification inside that card --------------
                    Repeater {
                        model: ScriptModel {
                            values: card.expanded ? card.notifications : card.notifications.slice(0, 1)
                        }
                        delegate: ColumnLayout {
                            id: notifRow
                            required property var modelData

                            readonly property var notification: notifRow.modelData
                            property bool replying: false
                            readonly property bool canReply: (notifRow.notification?.replyId ?? "") !== ""

                            Layout.fillWidth: true
                            spacing: Appearance.spacing.space50

                            StyledText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: notifRow.notification?.title ?? ""
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: notifRow.notification?.text ?? ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Appearance.spacing.space50

                                NotificationActionButton {
                                    id: dismissButton
                                    implicitWidth: dismissButton.contentItem.implicitWidth
                                        + dismissButton.leftPadding + dismissButton.rightPadding
                                    onClicked: PhoneNotifications.dismiss(notifRow.notification.publicId)

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "close"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: Appearance.colors.colOnLayer2
                                    }

                                    StyledToolTip {
                                        text: Translation.tr("Dismiss")
                                    }
                                }

                                NotificationActionButton {
                                    id: replyButton
                                    visible: notifRow.canReply
                                    implicitWidth: replyButton.contentItem.implicitWidth
                                        + replyButton.leftPadding + replyButton.rightPadding
                                    toggled: notifRow.replying
                                    onClicked: notifRow.replying = !notifRow.replying

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "reply"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: Appearance.colors.colOnLayer2
                                    }

                                    StyledToolTip {
                                        text: Translation.tr("Reply")
                                    }
                                }

                                Repeater {
                                    model: ScriptModel {
                                        values: notifRow.notification?.actions ?? []
                                    }
                                    delegate: NotificationActionButton {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        buttonText: modelData
                                        onClicked: PhoneNotifications.sendAction(notifRow.notification.publicId, modelData)
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                NotificationActionButton {
                                    id: copyButton
                                    implicitWidth: copyButton.contentItem.implicitWidth
                                        + copyButton.leftPadding + copyButton.rightPadding
                                    onClicked: {
                                        Quickshell.clipboardText = [notifRow.notification?.title ?? "",
                                                                    notifRow.notification?.text ?? ""]
                                            .filter(part => part !== "").join("\n");
                                        copyGlyph.text = "inventory";
                                        copiedTimer.restart();
                                    }

                                    Timer {
                                        id: copiedTimer
                                        interval: 1500
                                        onTriggered: copyGlyph.text = "content_copy"
                                    }

                                    contentItem: MaterialSymbol {
                                        id: copyGlyph
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "content_copy"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: Appearance.colors.colOnLayer2
                                    }

                                    StyledToolTip {
                                        text: Translation.tr("Copy")
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: notifRow.replying && notifRow.canReply
                                spacing: Appearance.spacing.space50

                                ToolbarTextField {
                                    id: replyField
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    colBackground: Appearance.colors.colLayer3
                                    placeholderText: Translation.tr("Reply…")
                                    onAccepted: replySendButton.send()
                                }

                                NotificationActionButton {
                                    id: replySendButton
                                    implicitWidth: replySendButton.contentItem.implicitWidth
                                        + replySendButton.leftPadding + replySendButton.rightPadding
                                    enabled: replyField.text.length > 0

                                    function send(): void {
                                        if (replyField.text.length === 0) return;
                                        PhoneNotifications.reply(notifRow.notification.publicId, replyField.text);
                                        replyField.text = "";
                                        notifRow.replying = false;
                                    }

                                    onClicked: replySendButton.send()

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "send"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
