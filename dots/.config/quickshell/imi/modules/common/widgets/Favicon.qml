import qs.modules.common
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell.Widgets

/**
 * A site icon, round. It draws the file at `iconPath` once `ready` says the
 * file is there; fetching it is the Favicons service's job, and which URL it
 * stands for is the host's.
 */
IconImage {
    id: root
    property string iconPath: ""
    property bool ready: false
    property real size: 32

    source: root.ready && root.iconPath !== "" ? Qt.resolvedUrl(root.iconPath) : ""
    implicitSize: root.size

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.implicitSize
            height: root.implicitSize
            radius: Appearance.rounding.full
        }
    }
}
