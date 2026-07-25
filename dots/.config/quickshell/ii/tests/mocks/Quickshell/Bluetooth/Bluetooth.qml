pragma Singleton
import QtQuick

// Mock of Quickshell.Bluetooth's Bluetooth singleton, shaped after what
// services/BluetoothStatus.qml reads. `defaultAdapter` is a var so tests can
// substitute a plain JS object ({ enabled, devices: { values: [...] } });
// devices connected through the default adapter must be BluetoothDevice
// instances because BluetoothStatus.firstActiveDevice is typed.
QtObject {
    property var defaultAdapter: null

    property QtObject adapters: QtObject {
        property var values: []
    }

    property QtObject devices: QtObject {
        property var values: []
    }
}
