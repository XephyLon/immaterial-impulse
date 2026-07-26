import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay

OsdTextIndicator {
    icon: "keyboard_capslock"
    name: Translation.tr("Caps Lock")
    value: KeyboardLocks.capsLockOn ? Translation.tr("On") : Translation.tr("Off")
}
