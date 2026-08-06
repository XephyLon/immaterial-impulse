import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Phone")
    icon: PhoneConnect.materialSymbol

    available: PhoneConnect.available
    toggled: PhoneConnect.activeDevice !== null
    statusText: {
        const device = PhoneConnect.activeDevice;
        if (!device) return Translation.tr("Disconnected");
        if (device.batteryAvailable) return `${device.name} • ${device.batteryCharge}%`;
        return device.name;
    }
    tooltipText: Translation.tr("Phone Connect | Click for devices")

    // A status tile, not an on/off switch - there is no daemon the shell
    // should be starting or stopping here. Every click lands on the device
    // dialog; the style buttons route their plain click there too.
    mainAction: null
    hasMenu: true
}
