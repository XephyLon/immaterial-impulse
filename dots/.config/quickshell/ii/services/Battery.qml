pragma Singleton

import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import Quickshell.Io

Singleton {
    id: root
    // Raw, unfiltered display-device readings. UPower.displayDevice transiently
    // swaps to a placeholder (isLaptopBattery=false, percentage=0) during
    // hardware/D-Bus churn; binding directly to it made the battery widget flap
    // in and out and fired false low-battery notifications (and even
    // auto-suspend) on the transient 0%. See issue #33.
    readonly property bool rawAvailable: UPower.displayDevice?.isLaptopBattery ?? false
    readonly property real rawPercentage: UPower.displayDevice?.percentage ?? 1
    readonly property int rawState: UPower.displayDevice?.state ?? UPowerDeviceState.Unknown

    // Available if the display device is a battery, or any battery still exists in
    // the device list. The battery stays listed even while displayDevice
    // momentarily points at a placeholder, so this rides out transient swaps
    // without flapping - and a true desktop (no battery anywhere) stays false.
    readonly property bool available: rawAvailable
        || (UPower.devices?.values ?? []).some(d => d?.isLaptopBattery)

    // Only accept percentage/charge readings while the display device really is
    // the battery; a transient placeholder reports 0% and would otherwise trip
    // false low/critical/suspend actions. Freeze at the last good reading.
    property real percentage: 1
    property var chargeState: UPowerDeviceState.Unknown

    function syncBattery() {
        if (!rawAvailable) return;
        percentage = rawPercentage;
        chargeState = rawState;
    }
    onRawAvailableChanged: syncBattery()
    onRawPercentageChanged: syncBattery()
    onRawStateChanged: syncBattery()
    Component.onCompleted: syncBattery()

    property bool isCharging: chargeState == UPowerDeviceState.Charging
    property bool isPluggedIn: isCharging || chargeState == UPowerDeviceState.PendingCharge
    readonly property bool allowAutomaticSuspend: Config.options.battery.automaticSuspend
    readonly property bool soundEnabled: Config.options.sounds.battery

    property bool isLow: available && (percentage <= Config.options.battery.low / 100)
    property bool isCritical: available && (percentage <= Config.options.battery.critical / 100)
    property bool isSuspending: available && (percentage <= Config.options.battery.suspend / 100)
    property bool isFull: available && (percentage >= Config.options.battery.full / 100)

    property bool isLowAndNotCharging: isLow && !isCharging
    property bool isCriticalAndNotCharging: isCritical && !isCharging
    property bool isSuspendingAndNotCharging: allowAutomaticSuspend && isSuspending && !isCharging
    property bool isFullAndCharging: isFull && isCharging

    property real energyRate: UPower.displayDevice.changeRate
    property real timeToEmpty: UPower.displayDevice.timeToEmpty
    property real timeToFull: UPower.displayDevice.timeToFull

    property real health: (function() {
        const devList = UPower.devices.values;
        for (let i = 0; i < devList.length; ++i) {
            const dev = devList[i];
            if (dev.isLaptopBattery && dev.healthSupported) {
                const health = dev.healthPercentage;
                if (health === 0) {
                    return 0.01;
                } else if (health < 1) {
                    return health * 100;
                } else {
                    return health;
                }
            }
        }
        return 0;
    })()

    property int chargeCycles: (function() {
        const devList = UPower.devices.values;
        for (let i = 0; i < devList.length; ++i) {
            const dev = devList[i];
            if (dev.isLaptopBattery) {
                return dev.chargeCycles ?? -1
            }
        }
        return -1
    })()

    onIsLowAndNotChargingChanged: {
        if (!root.available || !isLowAndNotCharging) return;
        Quickshell.execDetached([
            "notify-send", 
            Translation.tr("Low battery"), 
            Translation.tr("Consider plugging in your device"), 
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
        ])

        if (root.soundEnabled) Audio.playSystemSound("dialog-warning");
    }

    onIsCriticalAndNotChargingChanged: {
        if (!root.available || !isCriticalAndNotCharging) return;
        Quickshell.execDetached([
            "notify-send", 
            Translation.tr("Critically low battery"), 
            Translation.tr("Please charge!\nAutomatic suspend triggers at %1%").arg(Config.options.battery.suspend), 
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
        ]);

        if (root.soundEnabled) Audio.playSystemSound("suspend-error");
    }

    onIsSuspendingAndNotChargingChanged: {
        if (root.available && isSuspendingAndNotCharging) {
            Quickshell.execDetached(["bash", "-c", `systemctl suspend || loginctl suspend`]);
        }
    }

    onIsFullAndChargingChanged: {
        if (!root.available || !isFullAndCharging) return;
        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Battery full"),
            Translation.tr("Please unplug the charger"),
            "-a", "Shell",
            "--hint=int:transient:1",
        ]);

        if (root.soundEnabled) Audio.playSystemSound("complete");
    }

    onIsPluggedInChanged: {
        if (!root.available || !root.soundEnabled) return;
        if (isPluggedIn) {
            Audio.playSystemSound("power-plug")
        } else {
            Audio.playSystemSound("power-unplug")
        }
    }
}
