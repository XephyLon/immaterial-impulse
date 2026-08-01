import qs.services
import QtQuick
import qs.modules.imi.onScreenDisplay

OsdTextIndicator {
    icon: "keyboard"
    name: Translation.tr("Keyboard Layout")
    value: HyprlandXkb.currentLayoutName
}
