import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay

OsdTextIndicator {
    icon: "keyboard"
    name: Translation.tr("Keyboard Layout")
    value: HyprlandXkb.currentLayoutName
}
