pragma Singleton
import QtQuick

// Mock of Quickshell.Services.UPower's UPower singleton. Every property that
// services/Battery.qml binds to is declared mutable so tests can drive the
// battery state machine directly.
QtObject {
    property QtObject displayDevice: QtObject {
        property bool isLaptopBattery: false
        property int state: 0 // UPowerDeviceState.Unknown
        property real percentage: 1.0
        property real changeRate: 0
        property real timeToEmpty: 0
        property real timeToFull: 0
    }

    // Battery.health / Battery.chargeCycles walk UPower.devices.values.
    // Plain JS objects are fine as entries.
    property QtObject devices: QtObject {
        property var values: []
    }
}
