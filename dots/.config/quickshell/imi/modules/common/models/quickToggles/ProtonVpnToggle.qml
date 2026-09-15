import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Proton VPN")
    icon: ProtonVpn.materialSymbol

    available: ProtonVpn.available
    toggled: ProtonVpn.connected
    statusText: {
        if (ProtonVpn.transitioning) return ProtonVpn.state === "Disconnecting" ? Translation.tr("Disconnecting…") : Translation.tr("Connecting…");
        if (!ProtonVpn.connected) return Translation.tr("Off");
        return ProtonVpn.server.length > 0 ? ProtonVpn.server : Translation.tr("On");
    }
    tooltipText: ProtonVpn.connected
        ? Translation.tr("Proton VPN | %1 · click to disconnect").arg(ProtonVpn.server)
        : Translation.tr("Proton VPN | Click to connect to the fastest server")

    mainAction: () => ProtonVpn.toggle()
}
