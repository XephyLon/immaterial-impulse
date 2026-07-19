import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.quickToggles.classicStyle

AbstractQuickPanel {
    id: root
    Layout.alignment: Qt.AlignHCenter
    implicitWidth: buttonGroup.implicitWidth
    implicitHeight: buttonGroup.implicitHeight
    color: "transparent"

    ButtonGroup {
        id: buttonGroup
        spacing: Appearance.spacing.space100
        padding: Appearance.spacing.space100
        color: Appearance.colors.colLayer1

        NetworkToggle {
            altAction: () => {
                root.openWifiDialog();
            }
        }
        BluetoothToggle {
            altAction: () => {
                root.openBluetoothDialog();
            }
        }
        NightLight {}
        GameMode {}
        IdleInhibitor {}
        EasyEffectsToggle {}
        CloudflareWarp {}
    }
}
