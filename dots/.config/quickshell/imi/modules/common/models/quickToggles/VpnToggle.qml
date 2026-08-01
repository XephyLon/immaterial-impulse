import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("VPN")
    icon: Vpn.anyActive ? "vpn_lock" : "vpn_key"

    available: Vpn.connections.length > 0
    toggled: Vpn.anyActive
    statusText: {
        const active = Vpn.activeConnections;
        if (active.length === 0) return Translation.tr("Off");
        if (active.length === 1) return active[0].name;
        return Translation.tr("%1 active").arg(active.length);
    }
    tooltipText: Translation.tr("VPN (NetworkManager)")

    mainAction: () => {
        if (Vpn.anyActive)
            Vpn.deactivateAll();
        else if (Vpn.connections.length > 0)
            Vpn.toggleConnection(Vpn.connections[0]);
    }
}
