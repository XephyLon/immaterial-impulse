import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The bar's mail badge: the notification bell's grammar (a glyph with a
// count dot) on the connected account's inbox. Takes no room until an
// account with mail on has answered once; click opens the inbox.
MouseArea {
    id: root
    property bool vertical: false

    readonly property bool shown: Gmail.enabled && Gmail.synced
    readonly property int unread: Gmail.unread
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    readonly property color glyphColor: Config.options.bar.cornerStyle === 3 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1

    visible: implicitWidth > 0
    enabled: shown
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    implicitWidth: shown ? (vertical ? Appearance.sizes.verticalBarWidth : glyph.implicitWidth + Appearance.spacing.space100) : 0
    implicitHeight: vertical ? glyph.implicitHeight + Appearance.spacing.space100 : Appearance.sizes.barHeight
    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    onClicked: Gmail.openInbox()

    MaterialSymbol {
        id: glyph
        anchors.centerIn: parent
        text: root.unread > 0 ? "mark_email_unread" : "mail"
        iconSize: Appearance.font.pixelSize.larger
        color: root.glyphColor

        Presence {
            shown: root.unread > 0
            anchors {
                right: parent.right
                top: parent.top
                rightMargin: root.showUnreadCount ? -Appearance.spacing.space50 : 1
                topMargin: root.showUnreadCount ? -Appearance.spacing.space25 : 3
            }
            z: 1
            Rectangle {
                radius: Appearance.rounding.full
                color: Config.options.bar.cornerStyle === 3 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                implicitHeight: root.showUnreadCount ? Math.max(counter.implicitWidth, counter.implicitHeight) : 8
                implicitWidth: implicitHeight
                StyledText {
                    id: counter
                    visible: root.showUnreadCount
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Config.options.bar.cornerStyle === 3 ? Appearance.colors.colPrimary : Appearance.colors.colLayer0
                    text: root.unread > 99 ? "99+" : root.unread
                }
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.shown && root.containsMouse
        text: root.unread > 0
            ? Translation.tr("%1 unread in %2 — click to open").arg(root.unread).arg(GoogleAccount.email)
            : Translation.tr("Inbox zero — click to open %1").arg(GoogleAccount.email)
    }
}
