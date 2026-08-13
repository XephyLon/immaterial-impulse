import qs.modules.common
import QtQuick

/**
 * How a shared element TRAVELS between the places its spans put it.
 *
 * One spelling, because there were twenty-three: the media tree alone wrote
 * this animation out twenty times, and weather and currency each declared a
 * private `component TravelBehavior` saying the same thing. A tree that
 * spells its own is a tree that can drift from the others by a curve.
 *
 *     Behavior on x { SpanTravel {} }
 */
NumberAnimation {
    duration: Appearance.animation.elementMove.duration
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
}
