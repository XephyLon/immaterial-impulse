import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls

/**
 * The editor's floating plate, once: shadow, `colLayer0` fill, the standard
 * `colLayer0Border` outline (the shell's rule for a standalone surface) and
 * the enter/exit tiers. The kind menu, the icon picker and the chip input's
 * suggestion menu are all this with content.
 */
Popup {
    id: root

    property real plateRadius: Appearance.rounding.normal

    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            property: "scale"
            from: 0.96
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    exit: Transition {
        NumberAnimation {
            property: "opacity"
            to: 0
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            property: "scale"
            to: 0.96
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
    }

    background: Item {
        // The shadow is the plate's sibling, painted first; nested inside
        // the plate it would sit over the fill and break under `clip`.
        StyledRectangularShadow {
            target: plate
        }
        Rectangle {
            id: plate
            anchors.fill: parent
            radius: root.plateRadius
            color: Appearance.colors.colLayer0
            border.width: Appearance.borderWidth.standard
            border.color: Appearance.colors.colLayer0Border
        }
    }
}
