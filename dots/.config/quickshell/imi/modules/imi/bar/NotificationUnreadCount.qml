import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

MaterialSymbol {
    id: root
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    text: Notifications.silent ? "notifications_paused" : "notifications"
    iconSize: Appearance.font.pixelSize.larger
    color: Config.options.bar.cornerStyle === 3 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1

    // The badge fades rather than snapping when the last unread is read or
    // notifications are paused - the bell itself is what the bar's Revealer
    // slides away, this is the dot on it.
    Presence {
        shown: !Notifications.silent && Notifications.unread > 0
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: root.showUnreadCount ? 0 : 1
            topMargin: root.showUnreadCount ? 0 : 3
        }
        z: 1

        Rectangle {
            id: notifPing
            radius: Appearance.rounding.full
            color: Config.options.bar.cornerStyle === 3 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0

            implicitHeight: root.showUnreadCount ? Math.max(notificationCounterText.implicitWidth, notificationCounterText.implicitHeight) : 8
            implicitWidth: implicitHeight
            width: implicitWidth
            height: implicitHeight

            StyledText {
                id: notificationCounterText
                visible: root.showUnreadCount
                anchors.centerIn: parent
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Config.options.bar.cornerStyle === 3 ? Appearance.colors.colPrimary : Appearance.colors.colLayer0
                text: Notifications.unread
            }
        }
    }
}
