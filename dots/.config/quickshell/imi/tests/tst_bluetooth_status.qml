import QtQuick
import QtTest
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import testservices

// Behavioral tests for services/BluetoothStatus.qml, driven through the mock
// Bluetooth singleton (tests/mocks/Quickshell/Bluetooth). The service is
// loaded via the `testservices` registration module.
TestCase {
    name: "BluetoothStatusTest"

    // firstActiveDevice is a typed property, so adapter-level devices must be
    // real BluetoothDevice instances (mocked type), not plain JS objects.
    property BluetoothDevice keyboard: BluetoothDevice { name: "Keyboard"; connected: false; paired: true }
    property BluetoothDevice earbuds: BluetoothDevice { name: "Earbuds"; connected: true; paired: true }

    function init() {
        Bluetooth.defaultAdapter = null
        Bluetooth.adapters.values = []
        Bluetooth.devices.values = []
    }

    function test_defaults_without_adapter() {
        compare(BluetoothStatus.available, false)
        compare(BluetoothStatus.enabled, false)
        compare(BluetoothStatus.connected, false)
        compare(BluetoothStatus.activeDeviceCount, 0)
        verify(BluetoothStatus.firstActiveDevice === null)
        compare(BluetoothStatus.friendlyDeviceList.length, 0)
    }

    function test_available_tracks_adapter_presence() {
        Bluetooth.adapters.values = [{}]
        compare(BluetoothStatus.available, true)
        Bluetooth.adapters.values = []
        compare(BluetoothStatus.available, false)
    }

    function test_sort_puts_named_devices_before_mac_addresses() {
        var mac = { name: "AA-BB-CC-DD-EE-FF" }
        var named = { name: "Headphones" }
        verify(BluetoothStatus.sortFunction(mac, named) > 0)
        verify(BluetoothStatus.sortFunction(named, mac) < 0)

        // Lowercase MACs are recognized too.
        var lowerMac = { name: "aa-bb-cc-dd-ee-ff" }
        verify(BluetoothStatus.sortFunction(lowerMac, named) > 0)

        // Pins actual behavior: only the hyphen-separated form is treated as
        // a MAC; a colon-separated name sorts like a regular name.
        var colonMac = { name: "AA:BB:CC:DD:EE:FF" }
        verify(BluetoothStatus.sortFunction(colonMac, named) < 0) // ":" < "H"
    }

    function test_sort_is_alphabetical_within_each_group() {
        verify(BluetoothStatus.sortFunction({ name: "Alpha" }, { name: "Beta" }) < 0)
        verify(BluetoothStatus.sortFunction({ name: "Beta" }, { name: "Alpha" }) > 0)
        verify(BluetoothStatus.sortFunction(
            { name: "AA-00-00-00-00-00" }, { name: "BB-00-00-00-00-00" }) < 0)
    }

    function test_device_lists_partition_and_order() {
        Bluetooth.devices.values = [
            { name: "Zeta Speaker", connected: true, paired: true },
            { name: "Alpha Mouse", connected: false, paired: true },
            { name: "AA-BB-CC-DD-EE-FF", connected: false, paired: false },
            { name: "Buds", connected: true, paired: true }
        ]

        compare(BluetoothStatus.connected, true)

        compare(BluetoothStatus.connectedDevices.length, 2)
        compare(BluetoothStatus.connectedDevices[0].name, "Buds")
        compare(BluetoothStatus.connectedDevices[1].name, "Zeta Speaker")

        compare(BluetoothStatus.pairedButNotConnectedDevices.length, 1)
        compare(BluetoothStatus.pairedButNotConnectedDevices[0].name, "Alpha Mouse")

        compare(BluetoothStatus.unpairedDevices.length, 1)
        compare(BluetoothStatus.unpairedDevices[0].name, "AA-BB-CC-DD-EE-FF")

        // friendlyDeviceList = connected, then paired, then unpaired.
        var names = BluetoothStatus.friendlyDeviceList.map(d => d.name)
        compare(names, ["Buds", "Zeta Speaker", "Alpha Mouse", "AA-BB-CC-DD-EE-FF"])
    }

    function test_battery_suffix_requires_available_battery() {
        // No device / battery not reported -> empty suffix.
        compare(BluetoothStatus.formatBatterySuffix(null), "")
        compare(BluetoothStatus.formatBatterySuffix(undefined), "")
        compare(BluetoothStatus.formatBatterySuffix(keyboard), "")

        // Reported battery -> " • NN%" from the 0..1 fraction, rounded.
        var buds = { name: "Buds", batteryAvailable: true, battery: 0.85 }
        compare(BluetoothStatus.formatBatterySuffix(buds), " • 85%")
        compare(BluetoothStatus.formatBatterySuffix(
            { batteryAvailable: true, battery: 0.999 }), " • 100%")
        compare(BluetoothStatus.formatBatterySuffix(
            { batteryAvailable: true, battery: 0 }), " • 0%")

        // batteryAvailable false wins even if a stale value is present.
        compare(BluetoothStatus.formatBatterySuffix(
            { batteryAvailable: false, battery: 0.5 }), "")
    }

    function test_battery_suffix_upower_fallback() {
        // BlueZ Battery1 absent, but UPower exposes the device as a
        // power_supply with the MAC in its nativePath (HID controllers).
        UPower.devices.values = [
            { isLaptopBattery: true, nativePath: "BAT0", percentage: 0.99 },
            { isLaptopBattery: false,
              nativePath: "ps-controller-battery-14:3a:9a:7c:45:47",
              percentage: 0.45 }
        ]
        compare(BluetoothStatus.formatBatterySuffix(
            { batteryAvailable: false, address: "14:3A:9A:7C:45:47" }), " • 45%")

        // BlueZ battery wins over the fallback when both exist.
        compare(BluetoothStatus.formatBatterySuffix(
            { batteryAvailable: true, battery: 0.6,
              address: "14:3A:9A:7C:45:47" }), " • 60%")

        // No matching UPower device -> still empty.
        compare(BluetoothStatus.formatBatterySuffix(
            { batteryAvailable: false, address: "AA:BB:CC:DD:EE:FF" }), "")
        UPower.devices.values = []
    }

    function test_default_adapter_activity() {
        Bluetooth.defaultAdapter = ({
            enabled: true,
            devices: { values: [keyboard, earbuds] }
        })

        compare(BluetoothStatus.enabled, true)
        compare(BluetoothStatus.activeDeviceCount, 1)
        verify(BluetoothStatus.firstActiveDevice === earbuds)
    }

    function test_battery_level_comes_from_bluez_then_upower_then_nothing() {
        compare(BluetoothStatus.batteryLevelOf(null), -1)
        compare(BluetoothStatus.batteryLevelOf(undefined), -1)
        compare(BluetoothStatus.batteryLevelOf(keyboard), -1)
        compare(BluetoothStatus.batteryLevelOf({ batteryAvailable: true, battery: 0.85 }), 0.85)
        compare(BluetoothStatus.batteryLevelOf({ batteryAvailable: false, battery: 0.5 }), -1)

        UPower.devices.values = [
            { isLaptopBattery: true, nativePath: "BAT0", percentage: 0.99 },
            { isLaptopBattery: false, nativePath: "ps-controller-battery-14:3a:9a:7c:45:47", percentage: 0.45 }
        ]
        compare(BluetoothStatus.batteryLevelOf({ batteryAvailable: false, address: "14:3A:9A:7C:45:47" }), 0.45)
        compare(BluetoothStatus.batteryLevelOf({ batteryAvailable: true, battery: 0.6, address: "14:3A:9A:7C:45:47" }), 0.6)
        compare(BluetoothStatus.batteryLevelOf({ batteryAvailable: false, address: "AA:BB:CC:DD:EE:FF" }), -1)
        // The suffix is the level, formatted - never a second lookup.
        compare(BluetoothStatus.formatBatterySuffix({ batteryAvailable: false, address: "14:3A:9A:7C:45:47" }), " • 45%")
        UPower.devices.values = []
    }

    function test_battery_devices_are_the_connected_ones_with_a_level_in_sort_order() {
        UPower.devices.values = [
            { isLaptopBattery: false, nativePath: "hid-14:3a:9a:7c:45:47-battery", percentage: 0.3 }
        ]
        Bluetooth.devices.values = [
            { name: "Zeta Buds", connected: true, paired: true, batteryAvailable: true, battery: 0.9 },
            { name: "Pad", connected: true, paired: true, batteryAvailable: false, address: "14:3A:9A:7C:45:47" },
            { name: "Mute Mouse", connected: true, paired: true, batteryAvailable: false, address: "AA:BB:CC:DD:EE:FF" },
            { name: "Away Keys", connected: false, paired: true, batteryAvailable: true, battery: 0.1 }
        ]
        compare(BluetoothStatus.batteryDevices.map(d => d.name), ["Pad", "Zeta Buds"])
        compare(BluetoothStatus.lowestBatteryDevice.name, "Pad")

        Bluetooth.devices.values = []
        compare(BluetoothStatus.batteryDevices.length, 0)
        verify(BluetoothStatus.lowestBatteryDevice === null)
        UPower.devices.values = []
    }
}
