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

    visible: implicitWidth > 0
    enabled: shown
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    implicitWidth: shown ? (vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth) : 0
    implicitHeight: vertical ? pill.implicitHeight : Appearance.sizes.barHeight
    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    onClicked: Gmail.openInbox()

    // A standalone widget draws its own pill (the record and privacy pills'
    // grammar) on the neutral layer pair: the bar's group behind it is the
    // dark ground, and a bare glyph in the layer's on-colour vanished there.
    Rectangle {
        id: pill
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.vertical ? 0 : Appearance.sizes.barStandalonePillOffset
        anchors.horizontalCenterOffset: root.vertical ? Appearance.sizes.barStandalonePillOffset : 0
        radius: Appearance.rounding.full
        color: root.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.7
        transformOrigin: Item.Center
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        implicitWidth: glyph.implicitWidth + Appearance.spacing.space150 * 2
        implicitHeight: root.vertical
            ? glyph.implicitHeight + Appearance.spacing.space100
            : Appearance.sizes.barStandalonePillHeight

        MaterialSymbol {
            id: glyph
            anchors.centerIn: parent
            text: "mail"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1

            Presence {
                shown: root.unread > 0
                // Centred on the envelope's top-right corner, so a wider count
                // grows out in every direction instead of back over the glyph.
                anchors {
                    horizontalCenter: parent.right
                    verticalCenter: parent.top
                    horizontalCenterOffset: Appearance.spacing.space25
                    verticalCenterOffset: Appearance.spacing.space50
                }
                z: 1
                Rectangle {
                    radius: Appearance.rounding.full
                    // This widget draws its own layer-1 pill whatever the bar style,
                    // so the dot is always the layer pair (the bell branches on the
                    // third style because it sits on that style's primary plate).
                    color: Appearance.colors.colOnLayer1
                    // A hairline of the pill's own colour keeps the dot legible over the glyph's edge.
                    border.width: Appearance.borderWidth.standard
                    border.color: Appearance.colors.colLayer1
                    implicitHeight: root.showUnreadCount ? Math.max(counter.implicitWidth, counter.implicitHeight) + Appearance.spacing.space25 : 8
                    implicitWidth: implicitHeight
                    StyledText {
                        id: counter
                        visible: root.showUnreadCount
                        anchors.centerIn: parent
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colLayer1
                        text: root.unread > 99 ? "99+" : root.unread
                    }
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
