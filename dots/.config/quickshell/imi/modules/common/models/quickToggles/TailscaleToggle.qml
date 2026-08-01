import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Tailscale")
    icon: Tailscale.materialSymbol

    available: Tailscale.installed
    toggled: Tailscale.running
    statusText: {
        if (!Tailscale.running) return Translation.tr("Off");
        if (Tailscale.exitNodeActive) return Tailscale.currentExitNodeName;
        return Translation.tr("On");
    }
    tooltipText: Translation.tr("Tailscale | Right-click to pick an exit node")

    mainAction: () => Tailscale.toggle()
    hasMenu: true
}
