import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.phone
import QtQuick

/**
 * The phone's mirrored notifications, grouped by the app that posted them.
 *
 * This is the shell's own notification list (modules/common/widgets/
 * NotificationListView.qml) pointed at a different backend, and nothing
 * else. It used to be 429 lines that re-spelled the shared card from the
 * inside: the same 70px drag threshold, the same 0.3/0.1 neighbour lean, the
 * same dismiss animation - and then drifted from it, so a group of one drew
 * an expand chevron that expanded nothing while the original knew to hide it.
 *
 * What differs between the two backends is not a card. A phone notification
 * is a public id on a KDE Connect leaf, dismissed there, its actions are bare
 * Android keys, and it can be replied to inline when the posting app attached
 * a `replyId`. All of that lives in PhoneNotificationController; the service
 * carries each notification in the card's own vocabulary as well as the
 * daemon's.
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

    NotificationListView {
        id: listView
        anchors.fill: parent
        visible: root.count > 0
        clip: true
        controller: PhoneNotificationController {}
    }
}
