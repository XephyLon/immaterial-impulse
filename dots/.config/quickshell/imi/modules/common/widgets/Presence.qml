import QtQuick
import qs.modules.common

/**
 * An element that is never snapped in or out.
 *
 * Its one child fades in when `shown` and stays drawn until the fade out has
 * finished, and can give up its room along an axis on the same clock so its
 * neighbours slide rather than jump. One scalar, one tier, both directions -
 * the effects tier, because the state this follows is reversible and the
 * enter/exit pair's curves are directional.
 *
 * Expects one child, which sizes itself (this item reports the child's
 * implicit size, scaled to nothing along a collapsing axis while hidden). A
 * child that anchors to fill this item is fine when nothing collapses; a
 * collapsing child keeps its own size and is clipped, so it is not squashed
 * on the way out. Layout.* attributes go on this item.
 */
Item {
    id: root

    property bool shown: true
    property bool collapseVertical: false
    property bool collapseHorizontal: false
    // A small travel on the way in and out, in pixels, riding the same scalar.
    property real rise: 0

    readonly property Item child: root.children.length > 0 ? root.children[0] : null
    property real presence: root.shown ? 1 : 0
    Behavior on presence {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    opacity: root.presence
    visible: root.presence > 0
    clip: root.collapseVertical || root.collapseHorizontal
    implicitWidth: (root.child?.implicitWidth ?? 0) * (root.collapseHorizontal ? root.presence : 1)
    implicitHeight: (root.child?.implicitHeight ?? 0) * (root.collapseVertical ? root.presence : 1)
    transform: Translate {
        y: (1 - root.presence) * root.rise
    }
}
