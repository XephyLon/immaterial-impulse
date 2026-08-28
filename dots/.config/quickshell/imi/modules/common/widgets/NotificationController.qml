import qs.services
import QtQuick

/**
 * What a notification card is allowed to know about the thing it draws.
 *
 * The shell's own cards were written against services/Notifications.qml end
 * to end - dismissal went through `Notifications.discardNotification` with an
 * id the freedesktop server minted, and the popup half owned a timeout. A
 * phone notification is a public id on a KDE Connect leaf, dismissed on that
 * leaf, carrying a `replyId` and Android action keys. Because there was no
 * seam, the phone grew a second card: 429 lines that re-spelled the same 70px
 * drag threshold, the same 0.3/0.1 neighbour lean and the same dismiss
 * animation, and then drifted (a group of one drew an expand chevron the
 * shell's own card knows to hide).
 *
 * This is that seam, and it is deliberately the OPERATIONS only. It takes
 * whole notification objects rather than ids, so which id a backend dismisses
 * by stays its own business.
 *
 * The defaults here ARE the shell's freedesktop behaviour, so a card that
 * says nothing gets exactly what it had before.
 */
QtObject {
    id: root

    // Whether this backend can reply inline, and whether this notification
    // in particular offers it. The shell's server has no reply channel.
    readonly property bool supportsReply: false
    function canReply(notif): bool {
        return false;
    }

    function discard(notif): void {
        Notifications.discardNotification(notif.notificationId);
    }

    function timeout(notif): void {
        Notifications.timeoutNotification(notif.notificationId);
    }

    function cancelTimeout(notif): void {
        Notifications.cancelTimeout(notif.notificationId);
    }

    // The card draws `{ text, identifier }`. The freedesktop model already
    // carries that shape; a backend whose actions are bare strings maps them
    // HERE rather than in the card, and rather than in a service whose own
    // tests pin the daemon's shape.
    function actionsOf(notif): var {
        return notif?.actions ?? [];
    }

    // `action` is an entry of whatever `actionsOf` returned.
    function invokeAction(notif, action): void {
        Notifications.attemptInvokeAction(notif.notificationId, action.identifier);
    }

    function reply(notif, text): void {
    }

    // ---- the list's end of the same seam -------------------------------
    function appNames(popup: bool): var {
        return popup ? Notifications.popupAppNameList : Notifications.appNameList;
    }

    function groupForApp(appName: string, popup: bool): var {
        return popup ? Notifications.popupGroupsByAppName[appName]
            : Notifications.groupsByAppName[appName];
    }
}
