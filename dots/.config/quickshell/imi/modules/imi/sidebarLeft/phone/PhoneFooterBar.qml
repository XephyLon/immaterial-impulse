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

        RippleButtonWithIcon {
            id: syncButton
            materialIcon: "sync"
            mainText: ""
            enabled: root.online
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: PhoneNotifications.refresh()

            StyledToolTip {
                text: Translation.tr("Sync notifications")
            }
        }

        Rectangle {
            id: countPill
            Layout.fillWidth: true
            implicitHeight: 35
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

        RippleButtonWithIcon {
            id: clearButton
            materialIcon: root.count > 0 ? "delete_sweep" : "do_not_disturb_on"
            mainText: ""
            enabled: root.online && root.count > 0
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: PhoneNotifications.dismissAll()

            StyledToolTip {
                text: root.count > 0
                    ? Translation.tr("Dismiss all phone notifications")
                    : Translation.tr("No notifications to clear")
            }
        }
    }
}
