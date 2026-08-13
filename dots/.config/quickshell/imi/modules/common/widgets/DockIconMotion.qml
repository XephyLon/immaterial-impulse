import QtQuick
import qs.modules.common
import "../../imi/dock/dock_geometry.js" as DockGeometry

/**
 * M3 Expressive feedback motion for a dock icon. Wrap the icon's visuals in
 * this and drive it with declarative state; it owns transforms only (scale +
 * a translate along the dock's own axis), never layout size, so the dock
 * strip's thickness cannot churn.
 *
 * Priority: dragging suppresses everything; press squish beats hover lift;
 * the launch bounce runs independently on its own translate offset.
 */
Item {
    id: root

    property bool hovered: false
    property bool pressed: false
    property bool launching: false
    property bool dragging: false

    // Both offsets below are MAGNITUDES, and this is the direction they take.
    // They used to be bare negative y, which is correct at exactly one edge:
    // at the top it drives the icon into the screen edge, and at a side edge
    // it slides along the strip instead of rising out of it.
    readonly property string dockEdge: DockGeometry.normalizedEdge(
        Config.options?.dock.edge ?? "bottom")
    readonly property var liftVector: DockGeometry.inwardVector(root.dockEdge)

    property real hoverScale: 1.15
    property real pressScale: 0.92

    default property alias content: contentContainer.data

    readonly property real targetScale: dragging ? 1.0 : pressed ? pressScale : hovered ? hoverScale : 1.0

    Component.onDestruction: {
        bounceAnimation.stop();
        appearAnimation.stop();
    }

    // Hover lift target; springs via its own Behavior.
    property real liftOffset: (!dragging && hovered && !pressed) ? Appearance.spacing.space50 : 0
    Behavior on liftOffset {
        NumberAnimation {
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    // Launch bounce rides a separate offset so it composes with the lift.
    property real bounceOffset: 0
    SequentialAnimation {
        id: bounceAnimation
        running: root.launching && !root.dragging
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation {
            target: root
            property: "bounceOffset"
            to: Appearance.spacing.space100
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
        NumberAnimation {
            target: root
            property: "bounceOffset"
            to: 0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
        PauseAnimation {
            duration: Appearance.animation.elementMoveFast.duration
        }
    }

    // One-shot appear pop; consumer calls playAppear() (gated by
    // DockLaunchTracker.firstAppearance) from its Component.onCompleted.
    property real appearScale: 1
    property real appearOpacity: 1
    function playAppear() {
        appearAnimation.restart();
    }
    ParallelAnimation {
        id: appearAnimation
        NumberAnimation {
            target: root
            property: "appearScale"
            from: 0.6
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
        NumberAnimation {
            target: root
            property: "appearOpacity"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }

    Item {
        id: contentContainer
        anchors.fill: parent
        scale: root.targetScale * root.appearScale
        opacity: root.appearOpacity
        transform: Translate {
            x: (root.liftOffset + root.bounceOffset) * root.liftVector.x
            y: (root.liftOffset + root.bounceOffset) * root.liftVector.y
        }
        Behavior on scale {
            enabled: !root.dragging && !appearAnimation.running
            NumberAnimation {
                // Fast, non-bouncy on the way into a press; springy overshoot out.
                duration: root.pressed ? Appearance.animation.elementMoveFast.duration
                                       : Appearance.animation.elementMoveSmall.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.pressed ? Appearance.animationCurves.expressiveEffects
                                                 : Appearance.animationCurves.expressiveFastSpatial
            }
        }
    }
}
