import qs.modules.common
import QtQuick
import Qt5Compat.GraphicalEffects

/**
 * A label whose text glows in a slow sweep while something is happening -
 * the "thinking" treatment. Two copies of the same text: the dim base, and
 * a bright copy revealed only through a soft band that travels across the
 * word and loops. `running` gates the whole effect; still, it is just the
 * base text at full alpha, so a finished label costs nothing.
 *
 * Dumb on purpose: text, font and the two inks come from the caller.
 */
Item {
    id: root

    property string text: ""
    property alias font: baseText.font
    property color baseColor: Appearance.colors.colSubtext
    property color glowColor: Appearance.colors.colOnLayer1
    property bool running: false

    implicitWidth: baseText.implicitWidth
    implicitHeight: baseText.implicitHeight

    StyledText {
        id: baseText
        anchors.fill: parent
        text: root.text
        color: root.running ? root.baseColor : root.glowColor
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    Item {
        anchors.fill: parent
        visible: root.running

        StyledText {
            id: glowText
            anchors.fill: parent
            text: root.text
            font: baseText.font
            color: root.glowColor
        }

        layer.enabled: root.running
        layer.effect: OpacityMask {
            maskSource: Item {
                width: root.width
                height: root.height
                Rectangle {
                    id: band
                    width: Math.max(24, root.width * 0.45)
                    height: parent.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: "white" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    // The sweep: off the left edge to off the right, looped.
                    // Linear on purpose - a glow that eases reads as a pulse,
                    // not a passing light.
                    NumberAnimation on x {
                        running: root.running && root.visible
                        loops: Animation.Infinite
                        from: -band.width
                        to: root.width
                        duration: 1400
                    }
                }
            }
        }
    }
}
