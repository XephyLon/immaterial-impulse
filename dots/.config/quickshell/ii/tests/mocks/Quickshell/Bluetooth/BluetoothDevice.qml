import QtQuick

// Mock BluetoothDevice: the subset of the real type that
// services/BluetoothStatus.qml touches.
QtObject {
    property string name: ""
    property bool connected: false
    property bool paired: false
    property bool batteryAvailable: false
    property real battery: 0 // 0..1 fraction, like the real type
}
