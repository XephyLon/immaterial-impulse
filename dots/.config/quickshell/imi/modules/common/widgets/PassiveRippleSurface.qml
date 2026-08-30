import qs.modules.common
import QtQuick

/**
 * The pressed look of a control that keeps its own input.
 *
 * A ComboBox opens a popup on its press and an ItemDelegate reports the click
 * that chooses a row; neither can be a RippleButton, and for a year neither
 * drew a ripple, a lift, or anything but a colour swap - the one kind of
 * control in the shell that answered a press with nothing (maintainer,
 * 2026-08-30: "Check the ripple effect on this UI component in general.
 * Doesn't seem to exist"). This sits under such a control as its background
 * and draws what a RippleButton would: the host hands over its hover, its
 * press and where the press landed, and takes the lift back through
 * `interactionMotion.scale` onto ITSELF - the surface's own transform is
 * cleared so the content rides the lift with the plate (the grouped-list
 * plate had that bug first).
 */
RippleButton {
    id: root

    property bool hostHovered: false
    property bool hostDown: false
    property point hostPressPoint: Qt.point(width / 2, height / 2)

    passive: true
    transform: []
    interactionMotion.hovered: root.hostHovered
    interactionMotion.down: root.hostDown
    // The host dims itself when disabled; a surface that dimmed too would
    // double it (tests/lint_disabled_opacity.py), and a RippleButton also
    // drops its background when disabled, which a ComboBox's does not.
    interactionMotion.controlEnabled: true
    buttonColor: root.hostHovered ? root.colBackgroundHover : root.colBackground

    onHostDownChanged: {
        if (root.hostDown)
            root.startRipple(root.hostPressPoint.x, root.hostPressPoint.y);
        else
            root.fadeRipple();
    }
}
