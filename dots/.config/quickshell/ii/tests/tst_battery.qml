import QtQuick
import QtTest
import Quickshell.Services.UPower
import testservices

// Behavioral tests for services/Battery.qml, driven through the mock UPower
// singleton (tests/mocks/Quickshell/Services/UPower). The service is loaded
// via the `testservices` registration module (tests/imports/testservices).
//
// Config defaults these tests rely on (modules/common/Config.qml):
//   battery.low = 20, battery.critical = 5, battery.suspend = 3,
//   battery.full = 101 (i.e. "full" notification disabled),
//   battery.automaticSuspend = true, sounds.battery = false.
// Side-effect handlers only reach the mocked Quickshell.execDetached (a
// console.log no-op), so triggering thresholds here is safe.
TestCase {
    name: "BatteryTest"

    function init() {
        UPower.displayDevice.state = UPowerDeviceState.Unknown
        UPower.displayDevice.percentage = 1.0
        UPower.displayDevice.isLaptopBattery = false
        UPower.devices.values = []
    }

    function test_unavailable_never_reports_thresholds() {
        // No laptop battery: every threshold flag must stay false even at 0%.
        UPower.displayDevice.percentage = 0.0
        compare(Battery.available, false)
        compare(Battery.isLow, false)
        compare(Battery.isCritical, false)
        compare(Battery.isSuspending, false)
        compare(Battery.isFull, false)
    }

    function test_threshold_mapping_follows_config_percentages() {
        UPower.displayDevice.isLaptopBattery = true
        compare(Battery.available, true)

        // Config thresholds are integer percents; bindings divide by 100.
        UPower.displayDevice.percentage = 0.5
        compare(Battery.isLow, false)
        compare(Battery.isCritical, false)

        UPower.displayDevice.percentage = 0.20 // boundary: low uses <=
        compare(Battery.isLow, true)
        compare(Battery.isCritical, false)

        UPower.displayDevice.percentage = 0.05 // boundary: critical uses <=
        compare(Battery.isCritical, true)
        compare(Battery.isSuspending, false)

        UPower.displayDevice.percentage = 0.03 // boundary: suspend uses <=
        compare(Battery.isSuspending, true)
    }

    function test_full_threshold_of_101_disables_full_notification() {
        UPower.displayDevice.isLaptopBattery = true
        UPower.displayDevice.percentage = 1.0
        // battery.full defaults to 101 => percentage >= 1.01 is unreachable,
        // pinning the "101 means off" convention.
        compare(Battery.isFull, false)
    }

    function test_charging_state_mapping() {
        UPower.displayDevice.isLaptopBattery = true

        UPower.displayDevice.state = UPowerDeviceState.Discharging
        compare(Battery.isCharging, false)
        compare(Battery.isPluggedIn, false)

        UPower.displayDevice.state = UPowerDeviceState.Charging
        compare(Battery.isCharging, true)
        compare(Battery.isPluggedIn, true)

        // PendingCharge counts as plugged in but not charging.
        UPower.displayDevice.state = UPowerDeviceState.PendingCharge
        compare(Battery.isCharging, false)
        compare(Battery.isPluggedIn, true)
    }

    function test_low_battery_alarm_is_suppressed_while_charging() {
        UPower.displayDevice.isLaptopBattery = true
        UPower.displayDevice.state = UPowerDeviceState.Charging
        UPower.displayDevice.percentage = 0.10
        compare(Battery.isLow, true)
        compare(Battery.isLowAndNotCharging, false)
        compare(Battery.isCriticalAndNotCharging, false)
        compare(Battery.isSuspendingAndNotCharging, false)

        UPower.displayDevice.state = UPowerDeviceState.Discharging
        compare(Battery.isLowAndNotCharging, true)
    }

    function test_health_scales_fractions_and_flags_zero() {
        // Fraction (0..1) readings are rescaled to percent...
        UPower.devices.values = [{ isLaptopBattery: true, healthSupported: true, healthPercentage: 0.85 }]
        compare(Battery.health, 85)

        // ...already-percent readings pass through...
        UPower.devices.values = [{ isLaptopBattery: true, healthSupported: true, healthPercentage: 92 }]
        compare(Battery.health, 92)

        // ...and an exact 0 is mapped to the 0.01 sentinel.
        UPower.devices.values = [{ isLaptopBattery: true, healthSupported: true, healthPercentage: 0 }]
        compare(Battery.health, 0.01)
    }

    function test_health_skips_non_battery_and_unsupported_devices() {
        UPower.devices.values = [
            { isLaptopBattery: false, healthSupported: true, healthPercentage: 10 },
            { isLaptopBattery: true, healthSupported: false, healthPercentage: 20 },
            { isLaptopBattery: true, healthSupported: true, healthPercentage: 77 }
        ]
        compare(Battery.health, 77)

        UPower.devices.values = []
        compare(Battery.health, 0)
    }

    function test_charge_cycles_fall_back_to_minus_one() {
        UPower.devices.values = [{ isLaptopBattery: true, chargeCycles: 342 }]
        compare(Battery.chargeCycles, 342)

        // First laptop battery wins even when its cycle count is unknown.
        UPower.devices.values = [{ isLaptopBattery: true }]
        compare(Battery.chargeCycles, -1)

        UPower.devices.values = []
        compare(Battery.chargeCycles, -1)
    }
}
