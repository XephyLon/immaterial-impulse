pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.modules.common

Item {
    id: root
    anchors.fill: parent

    required property int clockSecond
    property real handWidth: 2 * Appearance.effectiveScale
    property real handLength: 95 * Appearance.effectiveScale
    property real dotSize: 14 * Appearance.effectiveScale
    property string style: "dot"
    property color color: Appearance.colors.colSecondary

    rotation: -90 + (360 / 60 * clockSecond)

    Behavior on rotation {
        enabled: Config.options.appearance.clock.analog.constantlyRotate
        RotationAnimation {
            direction: RotationAnimation.Clockwise
            duration: 1000
            easing.type: Easing.InOutQuad
        }
    }

    // "line" style: thin line hand
    Rectangle {
        visible: root.style === "line" || root.style === "classic"
        anchors.verticalCenter: parent.verticalCenter
        x: parent.width / 2 - (root.style === "classic" ? 20 * Appearance.effectiveScale : 0)
        width: root.handLength
        height: root.style === "classic" ? 3 * Appearance.effectiveScale : root.handWidth
        radius: height / 2
        color: root.color
    }

    // "classic" style: short tail going backwards
    Rectangle {
        visible: root.style === "classic"
        anchors.verticalCenter: parent.verticalCenter
        x: parent.width / 2 - 24 * Appearance.effectiveScale
        width: 20 * Appearance.effectiveScale
        height: 3 * Appearance.effectiveScale
        radius: 1.5 * Appearance.effectiveScale
        color: root.color
    }

    // "dot" style: circle at tip
    Rectangle {
        visible: root.style === "dot"
        width: root.dotSize
        height: root.dotSize
        radius: root.dotSize / 2
        color: root.color
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.horizontalCenter
            leftMargin: root.handLength - root.dotSize / 2
        }
    }
}
