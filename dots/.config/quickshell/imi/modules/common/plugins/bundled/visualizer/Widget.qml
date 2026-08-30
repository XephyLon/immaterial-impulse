pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import qs.modules.common
import qs.modules.common.plugins.designsystem.services
import "../../../functions/cavaBands.js" as CavaBands

Item {
    id: root

    // This widget is only built while the plugin is enabled (its host loader
    // follows the enabled list), so existing is most of the claim on cava -
    // which is the `plugins.enabled.includes("visualizer")` term the old
    // process gate read straight out of the config.
    //
    // `visible` adds the rest. Everything the desktop draws hangs off
    // `parallaxViewport`, which Background.qml switches off while a window is
    // fullscreen, and `visible` is the effective value - so this claim drops
    // when the wallpaper stops being drawn, without knowing why it stopped.
    CavaRef { active: root.visible }

    // The visualiser draws bars straight onto the wallpaper - it has no panel,
    // card or tint of its own - so it opts out of the host's frost entirely by
    // declaring an empty blur-region list. PluginWidget skips the blur surface
    // when a widget declares custom regions and supplies none.
    readonly property var blurRegions: []

    // The name of the monitor this instance lives on. PluginWidget knows it
    // (Background passes `screen.name`); PluginNode forwards it to any
    // component-backed widget that declares this property.
    property string screenName: ""
    // Same lookup idiom as services/Brightness.qml and the OSD modules: find the
    // ShellScreen whose name matches. The attached Screen of the window we are
    // in is the same monitor, so the fallback is correct on a secondary display
    // too - it only covers the window between load and the name arriving.
    readonly property var widgetScreen: Quickshell.screens.find(s => s.name === root.screenName) ?? null
    readonly property real targetScreenWidth: widgetScreen ? widgetScreen.width : Screen.width

    // Full-bleed, like the built-in this replaced. The manifest deliberately
    // declares no `grid`: the grid caps at 12 columns (1716px), which is a third
    // of a 5120px display, and a spectrum that stops a third of the way across
    // is not the widget. With no grid the host sizes us from our own implicit
    // size (manifest defaultWidth/Height act only as a floor), so we bind the
    // width to the real monitor. See docs/widget-grid.md.
    implicitWidth: Math.max(1, root.targetScreenWidth)
    implicitHeight: root.maxBarHeight + 20

    readonly property list<real> points: CavaService.values

    property real barWidth: 4
    property real barSpacing: Appearance.spacing.space100
    property real maxBarHeight: 220
    property real maxVisualizerValue: CavaService.maxValue
    // Temporal smoothing, as one exponential filter over the whole array on
    // each cava frame - NOT a `Behavior on height` per bar. On a 5120px
    // monitor this widget is 426 bars, and 426 NumberAnimations restarted
    // sixty times a second were 32 points of the shell's main-thread CPU
    // (86% with cava running, 54% with it paused, measured), on the thread
    // the sidebars' frame-driven slide runs on. The filter's time constant
    // matches the animation this replaces: at 60 frames/s, k = 0.35 settles
    // in about 150ms.
    property real smoothingFactor: 0.35
    property var displayed: []
    // Bar colour by intensity, primary container at rest to primary at full
    // height, in 32 steps.
    readonly property var palette: {
        const hi = Appearance.colors.colPrimary, lo = Appearance.colors.colPrimaryContainer;
        const out = [];
        for (let i = 0; i < 32; i++) {
            const t = i / 31;
            out.push(Qt.rgba(hi.r * t + lo.r * (1 - t), hi.g * t + lo.g * (1 - t), hi.b * t + lo.b * (1 - t), 1));
        }
        return out;
    }

    // Bars span the whole monitor again, at the built-in's density.
    readonly property int barCount: Math.max(1, Math.floor(root.targetScreenWidth / (barWidth + barSpacing)))

    readonly property var smoothedPoints: {
        let count = barCount
        let mapped = CavaBands.resample(root.points, count)

        let smoothed = new Array(count)
        let sW = 0.2
        for (let j = 0; j < count; j++) {
            let p = mapped[Math.max(0, j - 1)]
            let n = mapped[Math.min(count - 1, j + 1)]
            smoothed[j] = (p * sW) + (mapped[j] * (1.0 - 2 * sW)) + (n * sW)
        }
        return smoothed
    }

    property real activityOpacity: 0
    Behavior on activityOpacity {
        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
    }

    Timer {
        id: silenceTimer
        interval: 1000
        onTriggered: root.activityOpacity = 0
    }

    onPointsChanged: {
        if (points.some(p => p > 0)) {
            root.activityOpacity = 1.0
            silenceTimer.restart()
        }
        const target = root.smoothedPoints
        const count = target.length
        const prev = root.displayed
        const next = new Array(count)
        const k = root.smoothingFactor
        for (let j = 0; j < count; j++) {
            const was = prev[j] ?? 0
            next[j] = was + (target[j] - was) * k
        }
        root.displayed = next
    }

    Row {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.barSpacing
        opacity: root.activityOpacity

        Behavior on opacity {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: root.barCount
            Rectangle {
                required property int index
                width: root.barWidth
                property real pointValue: {
                    const v = root.displayed[index] ?? 0
                    return Math.max(root.barWidth, (v / root.maxVisualizerValue) * root.maxBarHeight)
                }
                height: pointValue
                topLeftRadius: root.barWidth / 2
                topRightRadius: root.barWidth / 2
                anchors.bottom: parent.bottom

                // A palette index, not four colour mixes per bar per frame:
                // the palette is rebuilt when the theme changes, which is
                // never sixty times a second.
                color: root.palette[Math.min(root.palette.length - 1,
                    Math.round((pointValue / root.maxBarHeight) * (root.palette.length - 1)))]

            }
        }
    }
}
