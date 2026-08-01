import qs.services
import QtQuick
import qs.modules.imi.onScreenDisplay

OsdTextIndicator {
    icon: "pin"
    name: Translation.tr("Num Lock")
    value: KeyboardLocks.numLockOn ? Translation.tr("On") : Translation.tr("Off")
}
