import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.notificationPopup
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * The real notification popup over a high-contrast backdrop, so one screenshot
 * says whether the compositor is frosting the cards.
 *
 * Nothing about this is reachable from qmltestrunner - Quickshell's plugin does
 * not load there, so Region cannot even be constructed - and weston implements
 * no ext-background-effect, so it runs under a nested Hyprland on an isolated
 * bus. See tests/run_notification_blur_probe.sh.
 *
 * The two control surfaces flank it: `probeStatic` publishes a region the way
 * the bar and the sidebars do (one declared Region over a fixed item), and
 * `probeUnblurred` publishes none at all. They bracket the answer - the
 * notification cards should read like the first and not like the second.
 */
Scope {
    id: probe

    PanelWindow {
        WlrLayershell.namespace: "quickshell:probeBackdrop"
        WlrLayershell.layer: WlrLayer.Background
        anchors { top: true; bottom: true; left: true; right: true }
        color: "black"

        Grid {
            anchors.fill: parent
            columns: 40
            Repeater {
                model: 40 * 40
                Rectangle {
                    required property int index
                    width: 40
                    height: 40
                    color: ((index + Math.floor(index / 40)) % 2 === 0) ? "white" : "black"
                }
            }
        }
    }

    PanelWindow {
        id: staticSurface
        WlrLayershell.namespace: "quickshell:probeStatic"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        mask: Region { item: staticCard }

        WindowBlurRegion {
            targetWindow: staticSurface
            regionItem: staticCard
            regionRadius: 20
        }

        Rectangle {
            id: staticCard
            x: 60
            y: 60
            width: 260
            height: 120
            radius: 20
            color: Appearance.colors.colBackgroundSurfaceContainer
        }
    }

    PanelWindow {
        id: unblurredSurface
        WlrLayershell.namespace: "quickshell:probeUnblurred"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        mask: Region { item: unblurredCard }

        Rectangle {
            id: unblurredCard
            x: 60
            y: 220
            width: 260
            height: 120
            radius: 20
            color: Appearance.colors.colBackgroundSurfaceContainer
        }
    }

    NotificationPopup {}

    Timer {
        interval: 2500
        running: true
        repeat: false
        onTriggered: console.log("[NotifBlurProbe] popups:", Notifications.popupList.length, "ready")
    }
}
