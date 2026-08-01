import QtQuick

import qs.modules.common

Loader {
    id: root
    property bool shown: true
    property alias fade: opacityBehavior.enabled

    // A Behavior's `animation` can only be assigned once - a caller can't override it via an
    // alias after this default is set (Qt silently keeps the default and logs "Cannot change
    // the animation assigned to a Behavior"). Expose the duration/easing as plain properties
    // instead and bind them inside a single NumberAnimation, so a caller that needs a different
    // enter/exit timing (see pluginLoader in Background.qml) can just override these properties.
    property int enterDuration: Appearance.animation.elementMoveFast.duration
    property var enterEasingCurve: Appearance.animation.elementMoveFast.bezierCurve
    property int exitDuration: Appearance.animation.elementMoveFast.duration
    property var exitEasingCurve: Appearance.animation.elementMoveFast.bezierCurve

    opacity: shown ? 1 : 0
    visible: opacity > 0
    active: opacity > 0

    Behavior on opacity {
        id: opacityBehavior
        NumberAnimation {
            duration: root.shown ? root.enterDuration : root.exitDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.shown ? root.enterEasingCurve : root.exitEasingCurve
        }
    }
}
