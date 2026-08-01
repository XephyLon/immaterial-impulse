import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

QuickToggleButton {
    id: root
    required property var connection

    buttonIcon: (connection?.active ?? false) ? "vpn_lock" : "vpn_key"
    toggled: connection?.active ?? false
    onClicked: Vpn.toggleConnection(root.connection)

    StyledToolTip {
        text: Translation.tr("VPN: %1").arg(root.connection?.name ?? "")
    }
}
