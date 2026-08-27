import QtQuick
import qs.modules.common

/**
 * Edit Mode's remove affordance: a small round badge riding a bar widget's or
 * a dock icon's corner while the mode is on.
 *
 * A `RippleButton`, not a hand-rolled MouseArea: the cursor, the hover and
 * press states and the single application of the interaction motion all come
 * from the control (the composites rule - anything scaling itself on a raw
 * hover/press flag inside one multiplies rather than replaces, and
 * lint_interaction_motion_double.py exists because two widgets shipped that
 * way). What this file adds is only the shape and the error-role colours: a
 * badge that removes something reads as destructive or it reads as
 * decoration.
 */
RippleButton {
    id: root

    implicitWidth: 18
    implicitHeight: 18
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.m3colors.m3errorContainer
    colBackgroundHover: Appearance.colors.colErrorHover
    colRipple: Appearance.colors.colErrorActive

    contentItem: MaterialSymbol {
        verticalAlignment: Text.AlignVCenter
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: "close"
        iconSize: 12
        color: Appearance.m3colors.m3onErrorContainer
    }
}
