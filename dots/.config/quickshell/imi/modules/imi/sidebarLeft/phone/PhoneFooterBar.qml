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
 * rather than the phone, so "0 notif." never stands in for "the phone is
 * not here".
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
                anchors.centerIn: parent
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
                text: root.online
                    ? Translation.tr("%1 notif.").arg(String(root.count))
                    : Translation.tr("Device offline")
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
