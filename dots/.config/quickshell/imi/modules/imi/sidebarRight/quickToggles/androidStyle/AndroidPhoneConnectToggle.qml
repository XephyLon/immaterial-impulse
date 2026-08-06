import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick

AndroidQuickToggleButton {
    id: root

    toggleModel: PhoneConnectToggle {}
    // The model has no primary action (nothing to toggle), so a plain click
    // on the compact tile opens the device dialog like the expanded tile's
    // menu click does.
    mainAction: () => root.openMenu()
}
