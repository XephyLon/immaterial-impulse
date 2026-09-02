import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool showDate: Config.options.bar.verbose
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Config.options.bar.cornerStyle === 3

    implicitWidth: root.vertical ? 32 : flow.implicitWidth + 4
    implicitHeight: root.vertical ? flow.implicitHeight + 4 : 32

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
    }

    GridLayout {
        id: flow
        anchors.centerIn: parent
        columns: root.vertical ? 1 : -1
        rows: root.vertical ? -1 : 1
        columnSpacing: isMaterial ? Appearance.spacing.space25 : Appearance.spacing.space125
        rowSpacing: columnSpacing

        Revealer {
            reveal: true
            MaterialSymbol {
                text: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                iconSize: Appearance.font.pixelSize.larger
                color: root.isMaterial ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
        }
        // Every icon that comes and goes does so through a Revealer: the row
        // slides closed over it instead of jumping when it leaves. Recorded
        // with a bare `visible:` on the bell: gone between two frames a sixth
        // of a second apart, the icons beside it snapping left.
        Revealer {
            reveal: Audio.source?.audio?.muted ?? false
            vertical: root.vertical
            MaterialSymbol {
                text: "mic_off"
                iconSize: Appearance.font.pixelSize.larger
                color: root.isMaterial ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
        }
        Loader {
            source: "HyprlandXkbIndicator.qml"
            onLoaded: item.color = root.isMaterial ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        }
        MaterialSymbol {
            text: Network.materialSymbol
            iconSize: Appearance.font.pixelSize.larger
            color: root.isMaterial ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        }
        Revealer {
            reveal: BluetoothStatus.available
            vertical: root.vertical
            MaterialSymbol {
                text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                iconSize: Appearance.font.pixelSize.larger
                color: root.isMaterial ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
        }
        Revealer {
            reveal: Vpn.anyActive
            vertical: root.vertical
            MaterialSymbol {
                text: Vpn.materialSymbol
                iconSize: Appearance.font.pixelSize.larger
                color: root.isMaterial ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
        }
        Revealer {
            id: notifRevealer
            reveal: Notifications.silent || Notifications.unread > 0
            vertical: root.vertical
            Loader {
                id: notifLoader
                // Stays loaded while the revealer is still closing over it,
                // so what slides away is the bell, not an empty gap.
                active: notifRevealer.reveal || notifRevealer.visible
                source: "NotificationUnreadCount.qml"
            }
        }
    }
}
