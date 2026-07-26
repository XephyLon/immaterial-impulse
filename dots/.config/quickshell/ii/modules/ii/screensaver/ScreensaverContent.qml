import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

Item {
    id: root

    property string mode: "black"
    property bool active: false

    // Fade the whole overlay in/out with a motion token.
    opacity: root.active ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    // Full black backdrop: pixels off for OLED burn-in protection in both modes.
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // "clock" mode: a dim clock that slowly drifts (pixel-shift) within bounds.
    Item {
        id: drift
        visible: root.mode === "clock"
        width: clockLabel.implicitWidth
        height: clockLabel.implicitHeight
        opacity: 0.4

        StyledText {
            id: clockLabel
            text: DateTime.time
            color: Appearance.m3colors.m3onBackground
            font.family: Appearance.font.family.lockscreenTimeFont
            font.pixelSize: Appearance.font.pixelSize.hugeass * 3
        }

        // Slow real-world drift; plain looping animations, not a motion token.
        SequentialAnimation on x {
            running: drift.visible
            loops: Animation.Infinite
            NumberAnimation {
                from: 0
                to: Math.max(0, root.width - drift.width)
                duration: 91000
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                from: Math.max(0, root.width - drift.width)
                to: 0
                duration: 91000
                easing.type: Easing.InOutSine
            }
        }

        SequentialAnimation on y {
            running: drift.visible
            loops: Animation.Infinite
            NumberAnimation {
                from: 0
                to: Math.max(0, root.height - drift.height)
                duration: 131000
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                from: Math.max(0, root.height - drift.height)
                to: 0
                duration: 131000
                easing.type: Easing.InOutSine
            }
        }
    }
}
