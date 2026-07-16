import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay

OsdTextIndicator {
    icon: "volume_up"
    name: Translation.tr("Output Device")
    value: Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : ""
}
