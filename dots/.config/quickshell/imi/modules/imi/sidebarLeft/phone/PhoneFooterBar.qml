import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The toolbar under the notification list: re-read the phone's
 * notifications, how many there are, dismiss them all.
 *
 * The count pill is deliberately not a button - there is nothing to do to a
 * number - and it says why the count is zero when the reason is the link
 * rather than the phone, so "0 notifications" never stands in for "the phone
 * is not here". The word is spelled out rather than abbreviated, in the
 * spelling `sidebarRight/notifications/NotificationList.qml` already uses for
 * the same count, so the two surfaces share one translation key - and the
 * singular is its own key, because `Translation.tr` takes one string and has
 * no plural form to select.
 *
 * The pill is the row's only `Layout.fillWidth` item, so it can never push
 * the two actions off the row - but its label was centred in it with nothing
 * bounding it, and a centred label paints straight over its neighbours rather
 * than eliding. The label is anchored to the pill's own box now.
 *
 * The two actions state BOTH of their dimensions
 * (`Appearance.sizes.phoneFooterButton*`) rather than sizing themselves from
 * their content. `RippleButtonWithIcon` measures a glyph plus a label, and
 * with the label empty its `Layout.fillWidth` slot still took the row's
 * leftover width - so each button came out 44x35, near enough square to read
 * as a circle under `rounding.full`, with the glyph drawn 2.5px left of the
 * button's own centre. An icon-only button is a `RippleButton` whose
 * contentItem is a `MaterialSymbol` declaring both alignments, which is what
 * centres a Control's content item (an anchor on it is decoration).
 */
Item {
    id: root

    property bool online: false
    readonly property int count: PhoneNotifications.count

    property real appear: 1

    implicitHeight: footerRow.implicitHeight

    RowLayout {
        id: footerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Appearance.spacing.space100

        RippleButton {
            id: syncButton
            implicitWidth: Appearance.sizes.phoneFooterButtonWidth
            implicitHeight: Appearance.sizes.phoneFooterButtonHeight
            enabled: root.online
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: PhoneNotifications.refresh()

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "sync"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledToolTip {
                text: Translation.tr("Sync notifications")
            }
        }

        Rectangle {
            id: countPill
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.phoneFooterButtonHeight
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            StyledText {
                anchors.fill: parent
                anchors.leftMargin: Appearance.spacing.space125
                anchors.rightMargin: Appearance.spacing.space125
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
                text: {
                    if (!root.online)
                        return Translation.tr("Device offline");
                    return root.count === 1
                        ? Translation.tr("1 notification")
                        : Translation.tr("%1 notifications").arg(String(root.count));
                }
            }
        }

        RippleButton {
            id: clearButton
            implicitWidth: Appearance.sizes.phoneFooterButtonWidth
            implicitHeight: Appearance.sizes.phoneFooterButtonHeight
            enabled: root.online && root.count > 0
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: PhoneNotifications.dismissAll()

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.count > 0 ? "delete_sweep" : "do_not_disturb_on"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSecondaryContainer
                animateChange: true
            }

            StyledToolTip {
                text: root.count > 0
                    ? Translation.tr("Dismiss all phone notifications")
                    : Translation.tr("No notifications to clear")
            }
        }
    }
}
