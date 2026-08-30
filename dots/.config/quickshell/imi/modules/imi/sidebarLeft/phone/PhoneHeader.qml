import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.phone
import "../../phone/device_glyph.js" as DeviceGlyph
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

        // The shared chip, not a chip of its own: the old PhoneDeviceChip was
        // 36 tall, fully round and always secondary-toned beside two 22px
        // pills, which is the size discrepancy the header wore. All three
        // sit at the chip height now, on one radius and one tone.
        FilterChip {
            id: deviceChip
            chipIcon: DeviceGlyph.forType(root.device?.type)
            label: root.device ? (root.device.name || root.device.id) : Translation.tr("No device")
            trailingIcon: PhoneConnect.devices.length > 0
                ? (root.rosterOpen ? "expand_less" : "expand_more") : ""
            // Selected: it IS the chosen device, and the tone is what the
            // two facts beside it wear.
            toggled: true
            enabled: PhoneConnect.devices.length > 0
            onClicked: root.toggleRoster()
        }

        Badge {
            id: connectionPill
            implicitHeight: deviceChip.implicitHeight
            // Metadata, not a control: a contained pill beside a chip reads
            // as clickable. M3E draws a status like this as an icon and a
            // label in on-surface-variant, with no container at all.
            colBackground: "transparent"
            colText: Appearance.colors.colOnSurfaceVariant
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
            implicitHeight: deviceChip.implicitHeight
            // Metadata, not a control: a contained pill beside a chip reads
            // as clickable. M3E draws a status like this as an icon and a
            // label in on-surface-variant, with no container at all.
            colBackground: "transparent"
            colText: Appearance.colors.colOnSurfaceVariant
            visible: root.device?.batteryAvailable ?? false
            badgeIcon: root.device?.batteryCharging ? "battery_charging_full" : "battery_full"
            label: Translation.tr("%1%").arg(String(root.device?.batteryCharge ?? 0))
        }

        Item {
            Layout.fillWidth: true
        }
    }
}
