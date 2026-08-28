import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The Phone tab's footer: sync, the count, and clear.
 *
 * It is the right sidebar's own notification status row, not a second one -
 * `ButtonGroup` and three `NotificationStatusButton`s, the same three roles in
 * the same order, so the two notification surfaces in this shell agree about
 * what that bar is. That component is where the M3 Expressive state morph
 * lives: `buttonRadius: baseHeight / 2` at rest against
 * `buttonRadiusPressed: Appearance.rounding.small`, and `clickedWidth` six
 * pixels wider than `baseWidth`, so a press squares the pill off and swells it
 * rather than only tinting it. Hand-rolled here, this bar had a fixed
 * `rounding.full` and no width response at all.
 *
 * It also ends a defect by deletion rather than by repair. The clear action
 * used to be a `RippleButton` whose contentItem carried `animateChange`, and
 * `StyledText`'s deferred swap animates the Text back to the `originalX`/
 * `originalY` it recorded in its own `Component.onCompleted` - which for a
 * Control's content item runs BEFORE the Control has placed it, so those are
 * (0, 0). Measured at 460px: after one count change the clear glyph settled
 * 4.00px left and 4.00px above centre, exactly the Control's padding, having
 * travelled 10.00px on the way, and faded to opacity 0.00 inside a pill that
 * does not fade. The shared button draws its glyph without that swap, so the
 * latch has nowhere to happen.
 */
Item {
    id: root

    property bool online: false
    readonly property int count: PhoneNotifications.count

    property real appear: 1

    implicitHeight: statusRow.implicitHeight

    ButtonGroup {
        id: statusRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        NotificationStatusButton {
            Layout.fillWidth: false
            buttonIcon: "sync"
            enabled: root.online
            onClicked: PhoneNotifications.refresh()

            StyledToolTip {
                text: Translation.tr("Sync notifications")
            }
        }

        // Not a button at all, and says so: the middle slot is the same
        // component held disabled, the way the right sidebar's row states its
        // own count. Drawing it as a Rectangle instead is what let this bar
        // drift a spacing step away from that one.
        NotificationStatusButton {
            enabled: false
            Layout.fillWidth: true
            buttonText: root.online
                ? (root.count === 1
                    ? Translation.tr("1 notification")
                    : Translation.tr("%1 notifications").arg(root.count))
                : Translation.tr("Device offline")
        }

        NotificationStatusButton {
            Layout.fillWidth: false
            buttonIcon: root.count > 0 ? "delete_sweep" : "do_not_disturb_on"
            enabled: root.online && root.count > 0
            onClicked: PhoneNotifications.dismissAll()

            StyledToolTip {
                text: root.count > 0
                    ? Translation.tr("Dismiss all phone notifications")
                    : Translation.tr("No notifications to clear")
            }
        }
    }
}
