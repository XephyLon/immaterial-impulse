pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => device.connected) ?? null
    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => device.connected).length ?? 0
    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)

    // " • NN%" for a device whose battery level is reported, "" otherwise.
    // Primary source is Quickshell.Bluetooth's BluetoothDevice (BlueZ Battery1
    // interface): `batteryAvailable` gates it, `battery` is a 0..1 fraction.
    // Many devices never get Battery1 (HID controllers like the DualSense, or
    // bluetoothd without Experimental=true), but the kernel exposes them as a
    // power_supply that UPower picks up with the MAC in its nativePath - fall
    // back to that, matched by address.
    function formatBatterySuffix(device) {
        if (device?.batteryAvailable)
            return ` • ${Math.round(device.battery * 100)}%`;
        const addr = device?.address?.toLowerCase() ?? "";
        if (addr) {
            const fallback = (UPower.devices?.values ?? []).find(d =>
                d && !d.isLaptopBattery && (d.nativePath ?? "").toLowerCase().includes(addr));
            if (fallback)
                return ` • ${Math.round(fallback.percentage * 100)}%`;
        }
        return "";
    }

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }
    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !d.connected).sort(sortFunction)
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]
}
