import qs.services
import QtQuick
import qs.modules.imi.onScreenDisplay

OsdTextIndicator {
    icon: "mic"
    name: Translation.tr("Input Device")
    value: Audio.source ? Audio.friendlyDeviceName(Audio.source) : ""
}
