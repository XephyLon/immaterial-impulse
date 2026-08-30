import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.modules.imi.sidebarRight.quickToggles.classicStyle
import qs.modules.common.models.quickToggles

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

        // Each tile is the shared model rendered classic-style; a right-click
        // on a model with a menu opens the panel's dialog for it.
        QuickToggleButton {
            toggleModel: NetworkToggle {}
            altAction: () => root.openWifiDialog()
        }
        QuickToggleButton {
            toggleModel: BluetoothToggle {}
            altAction: () => root.openBluetoothDialog()
        }
        QuickToggleButton {
            toggleModel: NightLightToggle {}
            altAction: () => root.openNightLightDialog()
        }
        QuickToggleButton { toggleModel: GameModeToggle {} }
        QuickToggleButton { toggleModel: InstantReplayToggle {} }
        QuickToggleButton { toggleModel: IdleInhibitorToggle {} }
        QuickToggleButton { toggleModel: EasyEffectsToggle {} }
        QuickToggleButton {
            toggleModel: TailscaleToggle {}
            altAction: () => root.openTailscaleDialog()
        }
        QuickToggleButton {
            toggleModel: PhoneConnectToggle {}
            altAction: () => root.openPhoneTab()
        }
        Repeater {
            model: Vpn.connections
            delegate: VpnConnectionToggle {
                required property var modelData
                connection: modelData
            }
        }
    }
}
