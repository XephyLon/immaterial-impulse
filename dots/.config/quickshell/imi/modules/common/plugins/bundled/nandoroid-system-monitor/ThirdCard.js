.pragma library

// Availability is the hard gate, not the option: without a battery,
// Battery.percentage sits at its 1.0 placeholder and an opted-in desktop would
// render a permanent, meaningless 100%. The option therefore only ever takes
// the battery away from a machine that has one, for the laptop user who put
// this widget on the desktop to watch disk.
//
// Lives here rather than inline in Widget.qml so the laptop branch is
// reachable from tests/tst_system_monitor_battery_card.qml, which runs on a
// machine with no battery.
function showsBattery(preferBattery, batteryAvailable) {
    return batteryAvailable === true && preferBattery !== false;
}
