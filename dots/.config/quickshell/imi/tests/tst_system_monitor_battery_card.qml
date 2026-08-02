import QtQuick
import QtTest
import Quickshell.Services.UPower
import testservices
import "../modules/common/plugins/bundled/nandoroid-system-monitor/ThirdCard.js" as ThirdCard

// The retired built-in resources widget swapped its third card to the battery
// whenever one existed; the nandoroid port that replaced it was always Disk.
// This pins the restored branch.
//
// The branch is unobservable on the machine this suite normally runs on - a
// desktop has no battery, so every live reading takes the Disk path. The mock
// UPower singleton (tests/mocks/Quickshell/Services/UPower) is what makes the
// laptop case reachable at all: it drives the real services/Battery.qml, so
// these assertions exercise the same `Battery.available` predicate the widget
// wrapper uses rather than a re-implementation of it.
TestCase {
    name: "SystemMonitorBatteryCardTest"

    function init() {
        UPower.displayDevice.isLaptopBattery = false
        UPower.displayDevice.percentage = 1.0
        UPower.displayDevice.state = UPowerDeviceState.Unknown
        UPower.devices.values = []
    }

    function test_desktop_with_no_battery_keeps_the_disk_card() {
        compare(Battery.available, false)
        compare(ThirdCard.showsBattery(true, Battery.available), false)
    }

    function test_laptop_gets_the_battery_card_without_being_asked() {
        UPower.displayDevice.isLaptopBattery = true
        compare(Battery.available, true)
        // `true` is the manifest default, so this is what an install that has
        // never opened the plugin's settings renders.
        compare(ThirdCard.showsBattery(true, Battery.available), true)
    }

    function test_option_puts_disk_back_on_a_laptop() {
        UPower.displayDevice.isLaptopBattery = true
        compare(ThirdCard.showsBattery(false, Battery.available), false)
    }

    function test_option_cannot_conjure_a_battery_on_a_desktop() {
        // Availability is the hard gate: without it the card would show
        // Battery.percentage's 1.0 placeholder as a permanent 100%.
        compare(ThirdCard.showsBattery(true, Battery.available), false)
    }

    function test_transient_upower_swap_does_not_flip_the_card_to_disk() {
        UPower.devices.values = [{ isLaptopBattery: true }]
        UPower.displayDevice.isLaptopBattery = true
        UPower.displayDevice.state = UPowerDeviceState.Discharging
        UPower.displayDevice.percentage = 0.42
        compare(ThirdCard.showsBattery(true, Battery.available), true)
        compare(Battery.percentage, 0.42)

        // UPower momentarily points displayDevice at a placeholder (issue #33).
        // Binding the card to `rawAvailable` would swap the whole third card to
        // Disk and back on every such churn; `available` rides it out.
        UPower.displayDevice.isLaptopBattery = false
        UPower.displayDevice.percentage = 0.0
        compare(ThirdCard.showsBattery(true, Battery.available), true)
        compare(Battery.percentage, 0.42)
    }
}
