import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The phone panel: one device on a chip with its state as pills, one row of
 * the actions the service answers, the notification area owning whatever
 * height is left, and the secondary features stacked at the bottom.
 *
 * Shaped after the fork's Phone tab (docs/proposals/phone-connect.md, "Prior
 * art") on the sidebar's own dialog pattern. Its action row carries six
 * buttons; ours carries the three this model backs - the other three are
 * scrcpy, a file picker and SFTP, which are drawn nowhere rather than drawn
 * dead. The roster of every device sits behind the chip's arrow.
 */
WindowDialog {
    id: root
    backgroundHeight: 600

    // Which device the chip, the pills and the action row are about: the
    // roster row the user picked, else the active device, else whichever is
    // first. Session state only - a persisted choice is the proposal's
    // slice 6.
    property string pickedDeviceId: ""
    property bool rosterOpen: false
    readonly property var shownDevice: PhoneConnect.devices.find(d => d.id === root.pickedDeviceId)
        ?? PhoneConnect.activeDevice
        ?? (PhoneConnect.devices[0] ?? null)
    readonly property bool shownOnline: root.shownDevice !== null
        && root.shownDevice.paired && root.shownDevice.reachable
    readonly property string shownAddress: root.shownDevice?.reachableAddresses?.[0] ?? ""

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space100

        WindowDialogTitle {
            Layout.fillWidth: true
            text: Translation.tr("Phone Connect")
        }

        DialogButton {
            id: refreshButton
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: implicitHeight

            onClicked: PhoneConnect.refresh()

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.centerIn: parent
                text: "refresh"
                iconSize: Appearance.font.pixelSize.larger
                color: refreshButton.colEnabled
            }

            StyledToolTip {
                text: Translation.tr("Refresh")
            }
        }
    }
    WindowDialogSeparator {}

    // ---- the device, and its state as pills ----
    Flow {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space100

        PhoneConnectDeviceChip {
            id: deviceChip
            device: root.shownDevice
            open: root.rosterOpen
            enabled: PhoneConnect.devices.length > 0
            onClicked: root.rosterOpen = !root.rosterOpen
        }
        Badge {
            id: connectionPill
            visible: root.shownDevice !== null
            badgeIcon: root.shownDevice?.reachable ? "wifi" : "wifi_off"
            label: !root.shownDevice?.reachable
                ? Translation.tr("Offline")
                : (root.shownAddress || Translation.tr("Connected"))
        }
        Badge {
            id: batteryPill
            visible: root.shownDevice?.batteryAvailable ?? false
            badgeIcon: root.shownDevice?.batteryCharging ? "battery_charging_full" : "battery_full"
            label: `${root.shownDevice?.batteryCharge ?? 0}%`
        }
        Badge {
            id: cellularPill
            visible: (root.shownDevice?.cellularNetworkType ?? "") !== ""
            badgeIcon: "signal_cellular_alt"
            label: root.shownDevice?.cellularNetworkType ?? ""
        }
    }

    // ---- the roster, behind the chip's arrow ----
    ColumnLayout {
        id: roster
        visible: root.rosterOpen
        Layout.fillWidth: true
        Layout.leftMargin: -root.contentPadding
        Layout.rightMargin: -root.contentPadding
        spacing: 0

        Repeater {
            model: ScriptModel {
                values: PhoneConnect.devices
            }
            delegate: PhoneConnectDeviceItem {
                required property var modelData
                device: modelData
                Layout.fillWidth: true
                active: root.shownDevice !== null && root.shownDevice.id === modelData.id
                onClicked: {
                    root.pickedDeviceId = modelData.id;
                    root.rosterOpen = false;
                }
            }
        }
    }

    // ---- one row of the actions the model answers ----
    RowLayout {
        id: actionRow
        Layout.alignment: Qt.AlignHCenter
        spacing: Appearance.spacing.space150

        PhoneConnectActionButton {
            id: ringButton
            glyph: "ring_volume"
            label: Translation.tr("Ring")
            enabled: root.shownOnline
            onClicked: PhoneConnect.ring(root.shownDevice)
        }
        PhoneConnectActionButton {
            id: pingButton
            glyph: "send"
            label: Translation.tr("Ping")
            visible: PhoneConnect.canPing
            enabled: root.shownOnline
            onClicked: PhoneConnect.ping(root.shownDevice)
        }
        PhoneConnectActionButton {
            id: clipboardButton
            glyph: "content_paste"
            label: Translation.tr("Send clipboard")
            visible: PhoneConnect.canSendClipboard
            enabled: root.shownOnline
            onClicked: PhoneConnect.sendClipboard(root.shownDevice)
        }
    }

    // ---- the notification area owns what is left ----
    PhoneConnectNotificationArea {
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

    // ---- the bottom stack: secondary features as cards ----
    Repeater {
        model: ScriptModel {
            values: PhoneConnect.pairingRequests
        }
        delegate: PhoneConnectPairingCard {
            required property var modelData
            device: modelData
            Layout.fillWidth: true
        }
    }

    WindowDialogSeparator {}
    WindowDialogButtonRow {
        StyledText {
            visible: PhoneConnect.available
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: PhoneConnect.backend === "kdeconnect"
                ? Translation.tr("Backend: KDE Connect")
                : Translation.tr("Backend: Valent")
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
