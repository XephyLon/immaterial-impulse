import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

QuickToggleButton {
    id: root
    visible: Tailscale.installed
    toggled: Tailscale.running
    buttonIcon: Tailscale.materialSymbol
    onClicked: Tailscale.toggle()

    StyledToolTip {
        text: Tailscale.exitNodeActive
            ? Translation.tr("Tailscale: exit node %1 | Right-click to configure").arg(Tailscale.currentExitNodeName)
            : Translation.tr("Tailscale | Right-click to pick an exit node")
    }
}
