import QtQuick
import qs.modules.common
import qs.modules.common.widgets
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

    // The shared model carries the hover and press progress on the right tiers
    // (a press is acknowledged faster than it is released, and a release
    // animates even when the pointer has already left). The icon's own
    // magnitudes stay its own - this reads the model's 0..1, not its scale.
    readonly property InteractionMotion motion: InteractionMotion {
        hovered: root.hovered && !root.dragging
        down: root.pressed && !root.dragging
    }
    readonly property real targetScale: root.dragging
        ? 1.0
        : 1 + (root.hoverScale - 1) * root.motion.hoverProgress
            + (root.pressScale - 1) * root.motion.pressProgress

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
        running: root.launching && !root.dragging && root.visible
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
        // No `Behavior on scale` here on purpose. Selecting the tier through a
        // binding on `duration`/`bezierCurve` hands the Behavior whichever tier
        // was current BEFORE the state changed - measured, a press played the
        // release's 999ms spring and a release played the press's 111ms curve,
        // exactly backwards. The scale is animated by the shared interaction
        // model instead, which writes the tier onto the animation and only then
        // writes the target.
    }
}
