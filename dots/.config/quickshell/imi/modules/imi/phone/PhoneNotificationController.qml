import qs
import qs.services
import qs.modules.common.widgets

/**
 * The phone's end of the notification card's backend seam.
 *
 * A phone notification is a PUBLIC id on a KDE Connect leaf: it is dismissed
 * on that leaf, its actions are bare Android keys rather than the
 * freedesktop model's `{ text, identifier }` pairs, and - unlike anything the
 * shell's own server offers - it can be replied to inline when the posting
 * app attached a `replyId`.
 *
 * Nothing here is a card: this is only what the shared card is not allowed to
 * assume, which is why the phone can now draw modules/common/widgets/
 * NotificationGroup.qml instead of the 429-line copy of it that used to live
 * beside this file.
 */
NotificationController {
    id: root

    readonly property bool supportsReply: true

    function canReply(notif): bool {
        return (notif?.replyId ?? "") !== "";
    }

    function discard(notif): void {
        PhoneNotifications.dismiss(notif.publicId);
    }
    // The phone's cards are in the LEFT sidebar. Before the seam carried this,
    // following a link from one closed the right sidebar instead.
    function openLink(link): void {
        Qt.openUrlExternally(link);
        GlobalStates.sidebarLeftOpen = false;
    }

    // The mirror has no popup half, so there is no timeout to run or cancel.
    function timeout(notif): void {
    }

    function cancelTimeout(notif): void {
    }

    // An Android action is a bare key. The card draws `{ text, identifier }`,
    // and the key is both.
    function actionsOf(notif): var {
        return (notif?.actions ?? []).map(key => ({ text: key, identifier: key }));
    }

    function invokeAction(notif, action): void {
        PhoneNotifications.sendAction(notif.publicId, action.identifier);
    }

    function reply(notif, text): void {
        PhoneNotifications.reply(notif.publicId, text);
    }

    function appNames(popup: bool): var {
        return PhoneNotifications.appNameList;
    }

    function groupForApp(appName: string, popup: bool): var {
        return PhoneNotifications.groupsByAppName[appName] ?? null;
    }
}
