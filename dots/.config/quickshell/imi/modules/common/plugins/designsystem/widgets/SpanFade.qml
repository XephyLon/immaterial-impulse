import qs.modules.common
import QtQuick

/**
 * How an element with no home at the next span LEAVES, and how one that
 * gains a home arrives. The counterpart to SpanTravel: travel is for what
 * exists on both sides, this is for what does not.
 *
 *     Behavior on opacity { SpanFade {} }
 */
NumberAnimation {
    duration: Appearance.animation.elementMove.duration
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Appearance.animationCurves.expressiveEffects
}
