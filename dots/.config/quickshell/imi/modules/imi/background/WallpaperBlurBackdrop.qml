import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions as CF

/**
 * The wallpaper, blurred, with a tint over it.
 *
 * Two surfaces want exactly this picture and for the same reason - the lock
 * screen, and Edit Mode's backdrop behind the shrunk desktop - so it is one
 * component rather than two GaussianBlurs that would drift a radius or a tint
 * apart. Only one of them is ever live: locking ends Edit Mode
 * (GlobalStates.onScreenLockedChanged).
 *
 * `source` is an item, not a path: a ShaderEffectSource renders its source
 * item in that item's OWN coordinate system, so this keeps working while the
 * wallpaper it samples is drawn inside a transformed viewport - which is the
 * whole reason Edit Mode's backdrop can stay full-screen while the desktop it
 * covers shrinks.
 */
GaussianBlur {
    id: root

    property real tintOpacity: 1

    Rectangle {
        anchors.fill: parent
        opacity: root.tintOpacity
        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
    }
}
