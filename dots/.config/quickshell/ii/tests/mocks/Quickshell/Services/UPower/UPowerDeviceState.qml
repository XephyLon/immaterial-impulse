import QtQuick

// Mock of the UPowerDeviceState enum namespace. Values mirror the real
// Quickshell/UPower codes. Battery.qml reads these as flat members
// (UPowerDeviceState.Charging), which QML resolves from the type's meta-enum.
QtObject {
    enum EnumValues {
        Unknown,        // 0
        Charging,       // 1
        Discharging,    // 2
        Empty,          // 3
        FullyCharged,   // 4
        PendingCharge,  // 5
        PendingDischarge // 6
    }
}
