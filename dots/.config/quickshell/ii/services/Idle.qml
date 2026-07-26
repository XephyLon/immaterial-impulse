pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root

    property alias inhibit: idleInhibitor.enabled
    inhibit: false

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.isNewHyprlandInstance) {
                root.inhibit = Persistent.states.idle.inhibit;
            } else {
                Persistent.states.idle.inhibit = root.inhibit;
            }
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    IdleInhibitor {
        id: idleInhibitor
        // A zwp_idle_inhibitor only takes effect while its surface is actually
        // mapped. A 0x0 window maps unreliably, so Hyprland's ext-idle-notify
        // (which hypridle reads) would sometimes ignore the inhibitor and the
        // session locked/hibernated anyway. Give it a reliably-mapped 1x1
        // transparent, input-transparent surface on the background layer so it
        // is present but never seen or interactable.
        window: PanelWindow {
            implicitWidth: 1
            implicitHeight: 1
            visible: true
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell:idleInhibitor"
            anchors {
                right: true
                bottom: true
            }
            // Input-transparent: clicks pass straight through.
            mask: Region {
                item: null
            }
        }
    }
}
