import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.phone
import QtQuick
import QtQuick.Layouts

/**
 * The Phone tab's top row: the device on a chip whose arrow opens the
 * roster, a connection pill and a battery pill.
 *
 * The connection pill says the most specific thing the daemon reported, in
 * that order: the cellular network type from connectivity_report ("LTE"),
 * else the first entry of reachableAddresses (the LAN address), else the
 * bare fact that the device is there. An unreachable device says so and
 * nothing else - an address is a claim about a link that is down.
 */
Item {
    id: root

    // The device the tab is about; null while the daemon knows none.
    property var device: null
    property bool rosterOpen: false
    readonly property bool online: root.device !== null
        && root.device.paired && root.device.reachable

    signal toggleRoster()

    // The wave member's one opt-in; StaggerEntrance installs the channels.
    property real appear: 1

    implicitHeight: headerRow.implicitHeight

    RowLayout {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Appearance.spacing.space100

        PhoneDeviceChip {
            id: deviceChip
            device: root.device
            open: root.rosterOpen
            enabled: PhoneConnect.devices.length > 0
            onClicked: root.toggleRoster()
        }

        Badge {
            id: connectionPill
            visible: root.device !== null
            badgeIcon: root.device?.reachable ? "wifi" : "wifi_off"
            label: {
                if (!root.device?.reachable) return Translation.tr("Offline");
                const cellular = root.device?.cellularNetworkType ?? "";
                if (cellular !== "") return cellular;
                const address = root.device?.reachableAddresses?.[0] ?? "";
                return address !== "" ? address : Translation.tr("Connected");
            }
        }

        Badge {
            id: batteryPill
            visible: root.device?.batteryAvailable ?? false
            badgeIcon: root.device?.batteryCharging ? "battery_charging_full" : "battery_full"
            label: Translation.tr("%1%").arg(String(root.device?.batteryCharge ?? 0))
        }

        Item {
            Layout.fillWidth: true
        }
    }
}
