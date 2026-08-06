import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

QuickToggleButton {
    id: root
    visible: PhoneConnect.available
    toggled: PhoneConnect.activeDevice !== null
    buttonIcon: PhoneConnect.materialSymbol
    // Nothing to toggle - a plain click opens the device dialog like the
    // right click does.
    onClicked: root.altAction?.()

    StyledToolTip {
        text: {
            const device = PhoneConnect.activeDevice;
            if (!device) return Translation.tr("Phone Connect | Click for devices");
            if (device.batteryAvailable)
                return Translation.tr("Phone Connect: %1 (%2%) | Click for devices").arg(device.name).arg(device.batteryCharge);
            return Translation.tr("Phone Connect: %1 | Click for devices").arg(device.name);
        }
    }
}
