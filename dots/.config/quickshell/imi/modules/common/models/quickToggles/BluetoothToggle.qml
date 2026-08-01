import QtQuick
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Bluetooth")
    statusText: {
        const device = BluetoothStatus.firstActiveDevice;
        if (!device)
            return Translation.tr("Not connected");
        return device.name + BluetoothStatus.formatBatterySuffix(device);
    }
    tooltipText: Translation.tr("%1 | Right-click to configure").arg(
        (BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Bluetooth"))
        + BluetoothStatus.formatBatterySuffix(BluetoothStatus.firstActiveDevice)
        + (BluetoothStatus.activeDeviceCount > 1 ? ` +${BluetoothStatus.activeDeviceCount - 1}` : "")
    )
    icon: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"

    available: BluetoothStatus.available
    toggled: BluetoothStatus.enabled
    mainAction: () => {
        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter?.enabled
    }
    hasMenu: true
}
