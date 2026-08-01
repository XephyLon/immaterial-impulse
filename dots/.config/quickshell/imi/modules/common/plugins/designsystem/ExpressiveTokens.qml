pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

Singleton {
    readonly property QtObject colors: Appearance.colors
    readonly property QtObject m3colors: Appearance.m3colors
    readonly property QtObject spacing: Appearance.spacing
    readonly property QtObject shape: Appearance.rounding
    readonly property QtObject typography: Appearance.font
    readonly property QtObject motion: Appearance.animation
    readonly property QtObject motionCurves: Appearance.animationCurves
    readonly property real scale: Appearance.effectiveScale
}
