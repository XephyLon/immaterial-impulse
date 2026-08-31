import qs.modules.common
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Notifications

Item { // Notification item area
    id: root
    property var notificationObject
    // See NotificationGroup: the operations this card is allowed to perform,
    // defaulting to the shell's own service.
    property NotificationController controller: NotificationController {}
    // Inline reply, which only some backends have: the freedesktop server has
    // no reply channel at all, and a phone notification has one only when the
    // posting app attached a `replyId`. Both questions are the controller's.
    readonly property bool canReply: root.controller.supportsReply
        && root.controller.canReply(root.notificationObject)
    property bool replying: false
    // The reply row's reveal, the way the card's own expansion moves: the
    // HEIGHT on the spatial curve (elementMove, the one the card's height
    // takes when it expands) and the contents fading on the faster effects
    // curve (elementMoveFast, the one the expanded body fades with). One
    // scalar for the height keeps the card's content height continuous both
    // ways - flipping `visible` removed the row in one frame while the card
    // was still shrinking, and the column spread the body text into the
    // slack.
    property real replyReveal: root.canReply && root.replying ? 1 : 0
    Behavior on replyReveal {
        NumberAnimation {
            id: replyRevealAnimation
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
    property bool expanded: false
    property bool onlyNotification: false
    property real fontSize: Appearance.font.pixelSize.small
    property real padding: onlyNotification ? 0 : Appearance.spacing.space100
    property real summaryElideRatio: 0.85

    property real dragConfirmThreshold: 70 // Drag further to discard notification
    property real dismissOvershoot: notificationIcon.implicitWidth + 20 // Account for gaps and bouncy animations
    property var qmlParent: root?.parent?.parent // There's something between this and the parent ListView
    property var parentDragIndex: qmlParent?.dragIndex ?? -1
    property var parentDragDistance: qmlParent?.dragDistance ?? 0
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance : 
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    implicitHeight: background.implicitHeight

    function destroyWithAnimation(left = false) {
        root.qmlParent.resetDrag()
        background.anchors.leftMargin = background.anchors.leftMargin; // Break binding
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }

    TextMetrics {
        id: summaryTextMetrics
        font.pixelSize: root.fontSize
        text: root.notificationObject.summary || ""
    }

    SequentialAnimation { // Drag finish animation
        id: destroyAnimation
        property bool left: true
        running: false

        NumberAnimation {
            target: background.anchors
            property: "leftMargin"
            to: (root.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        onFinished: () => {
            root.controller.discard(root.notificationObject);
        }
    }

    DragManager { // Drag manager
        id: dragManager
        anchors.fill: root
        anchors.leftMargin: root.expanded ? -notificationIcon.implicitWidth : 0
        interactive: expanded
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
                root.destroyWithAnimation();
            }
        }

        onDraggingChanged: () => {
            if (dragging) {
                root.qmlParent.dragIndex = root.index ?? root.parent.children.indexOf(root);
            }
        }

        onDragDiffXChanged: () => {
            root.qmlParent.dragDistance = dragDiffX;
        }

        onDragReleased: (diffX, diffY) => {
            if (Math.abs(diffX) > root.dragConfirmThreshold)
                root.destroyWithAnimation(diffX < 0);
            else 
                dragManager.resetDrag();
        }
    }

    NotificationAppIcon { // App icon
        id: notificationIcon
        appName: notificationObject.appName
        opacity: (!onlyNotification && notificationObject.image != "" && expanded) ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        image: notificationObject.image
        anchors.right: background.left
        anchors.top: background.top
        anchors.rightMargin: Appearance.spacing.space150
    }

    Rectangle { // Background of notification item
        id: background
        width: parent.width
        anchors.left: parent.left
        radius: Appearance.rounding.small
        anchors.leftMargin: root.xOffset

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        color: (expanded && !onlyNotification) ? 
            (notificationObject.urgency == NotificationUrgency.Critical) ? 
                ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colLayer2, 0.35) :
                (Appearance.colors.colLayer3) :
            ColorUtils.transparentize(Appearance.colors.colLayer3)

        implicitHeight: expanded ? (contentColumn.implicitHeight + padding * 2) : summaryRow.implicitHeight
        // Stands down while the reply row is revealing: that reveal is
        // already continuous, and a second easing chasing it left the card
        // taller than its content for a beat - slack the column spread the
        // body text into.
        Behavior on implicitHeight {
            enabled: !replyRevealAnimation.running
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout { // Content column
            id: contentColumn
            anchors.fill: parent
            anchors.margins: expanded ? root.padding : 0
            spacing: Appearance.spacing.space50

            Behavior on anchors.margins {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout { // Summary row
                id: summaryRow
                visible: !root.onlyNotification || !root.expanded
                Layout.fillWidth: true
                implicitHeight: summaryText.implicitHeight
                StyledText {
                    id: summaryText
                    Layout.fillWidth: summaryTextMetrics.width >= root.width * root.summaryElideRatio
                    visible: !root.onlyNotification
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colOnLayer3
                    elide: Text.ElideRight
                    text: root.notificationObject.summary || ""
                }
                StyledText {
                    opacity: !root.expanded ? 1 : 0
                    visible: opacity > 0
                    Layout.fillWidth: true
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap // Needed for proper eliding????
                    maximumLineCount: 1
                    textFormat: Text.StyledText
                    text: {
                        return NotificationUtils.processNotificationBody(notificationObject.body, notificationObject.appName || notificationObject.summary).replace(/\n/g, "<br/>")
                    }
                }
            }

            ColumnLayout { // Expanded content
                id: expandedContentColumn
                Layout.fillWidth: true
                opacity: root.expanded ? 1 : 0
                visible: opacity > 0

                StyledText { // Notification body (expanded)
                    id: notificationBodyText
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Layout.fillWidth: true
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    textFormat: Text.RichText
                    text: {
                        return `<style>img{max-width:${expandedContentColumn.width}px;}</style>` + 
                            `${NotificationUtils.processNotificationBody(notificationObject.body, notificationObject.appName || notificationObject.summary).replace(/\n/g, "<br/>")}`
                    }

                    // Which sidebar (if any) closes behind a followed link
                    // is the backend's to say: the shell's cards sit in the
                    // right sidebar, the phone's in the left.
                    onLinkActivated: link => root.controller.openLink(link)
                    
                    PointingHandLinkHover {}
                }

                Item {
                    Layout.fillWidth: true
                    implicitWidth: actionsFlickable.implicitWidth
                    implicitHeight: actionsFlickable.implicitHeight

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: actionsFlickable.width
                            height: actionsFlickable.height
                            radius: Appearance.rounding.small
                        }
                    }

                    ScrollEdgeFade {
                        target: actionsFlickable
                        vertical: false
                    }

                    StyledFlickable { // Notification actions
                        id: actionsFlickable
                        anchors.fill: parent
                        implicitHeight: actionRowLayout.implicitHeight
                        contentWidth: actionRowLayout.implicitWidth

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on height {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on implicitHeight {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        RowLayout {
                            id: actionRowLayout
                            Layout.alignment: Qt.AlignBottom
                            // As wide as the card when the chips fit, their
                            // own width when they do not (then the flickable
                            // scrolls). The chips share the room through
                            // fillWidth; the old arithmetic split the width
                            // in two by hand and put a third chip - Reply -
                            // off the edge.
                            width: Math.max(implicitWidth, actionsFlickable.width)

                            NotificationActionButton {
                                Layout.fillWidth: true
                                buttonText: Translation.tr("Close")
                                urgency: notificationObject.urgency

                                onClicked: {
                                    root.destroyWithAnimation()
                                }

                                contentItem: MaterialSymbol {
                                    verticalAlignment: Text.AlignVCenter
                                    iconSize: Appearance.font.pixelSize.larger
                                    horizontalAlignment: Text.AlignHCenter
                                    color: (notificationObject.urgency == NotificationUrgency.Critical) ? 
                                        Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface
                                    text: "close"
                                }
                            }

                            Repeater {
                                id: actionRepeater
                                model: root.controller.actionsOf(root.notificationObject)
                                NotificationActionButton {
                                    id: notifAction
                                    required property var modelData
                                    Layout.fillWidth: true
                                    buttonText: modelData.text
                                    urgency: notificationObject.urgency
                                    onClicked: {
                                        root.controller.invokeAction(root.notificationObject, modelData);
                                    }
                                }
                            }

                            NotificationActionButton {
                                id: replyToggle
                                visible: root.canReply
                                Layout.fillWidth: true
                                urgency: notificationObject.urgency
                                toggled: root.replying
                                onClicked: root.replying = !root.replying

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "reply"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: replyToggle.colText
                                }

                                StyledToolTip {
                                    text: Translation.tr("Reply")
                                }
                            }

                            NotificationActionButton {
                                Layout.fillWidth: true
                                urgency: notificationObject.urgency

                                onClicked: {
                                    Quickshell.clipboardText = notificationObject.body
                                    copyIcon.text = "inventory"
                                    copyIconTimer.restart()
                                }

                                Timer {
                                    id: copyIconTimer
                                    interval: 1500
                                    repeat: false
                                    onTriggered: {
                                        copyIcon.text = "content_copy"
                                    }
                                }

                                contentItem: MaterialSymbol {
                                    verticalAlignment: Text.AlignVCenter
                                    id: copyIcon
                                    iconSize: Appearance.font.pixelSize.larger
                                    horizontalAlignment: Text.AlignHCenter
                                    color: (notificationObject.urgency == NotificationUrgency.Critical) ? 
                                        Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface
                                    text: "content_copy"
                                }
                            }
                            
                        }
                    }
                }

                // The reply field, under the actions rather than among them:
                // it is a text entry and they are chips, and it is present
                // only while the user is actually replying.
                Item {
                    Layout.fillWidth: true
                    // Always laid out, never toggled: flipping `visible` made
                    // the column add or drop its spacing in one frame, a 6px
                    // snap at each end of an otherwise eased reveal. The
                    // spacing rides the reveal instead, as a margin that
                    // cancels it while the row is away.
                    visible: root.canReply
                    Layout.topMargin: -(parent?.spacing ?? 0) * (1 - root.replyReveal)
                    opacity: root.replying ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    clip: true
                    implicitHeight: replyRow.implicitHeight * root.replyReveal
                    RowLayout {
                    id: replyRow
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    spacing: Appearance.spacing.space50

                    ToolbarTextField {
                        id: replyField
                        Layout.fillWidth: true
                        // The chip height, with padding that fits it: the
                        // field's default 12px padding around a 14px font
                        // wants 38, and squeezed to 34 it drew its text past
                        // the top edge.
                        implicitHeight: 34
                        padding: Appearance.spacing.space100
                        colBackground: Appearance.colors.colLayer3
                        placeholderText: Translation.tr("Reply…")
                        onAccepted: replySendButton.send()
                    }

                    NotificationActionButton {
                        id: replySendButton
                        urgency: notificationObject.urgency
                        enabled: replyField.text.length > 0

                        function send(): void {
                            if (replyField.text.length === 0)
                                return;
                            root.controller.reply(root.notificationObject, replyField.text);
                            replyField.text = "";
                            root.replying = false;
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