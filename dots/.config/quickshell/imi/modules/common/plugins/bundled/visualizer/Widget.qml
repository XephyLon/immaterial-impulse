pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common

Item {
    id: root

    // The visualiser draws bars straight onto the wallpaper - it has no panel,
    // card or tint of its own - so it opts out of the host's frost entirely by
    // declaring an empty blur-region list. PluginWidget skips the blur surface
    // when a widget declares custom regions and supplies none.
    readonly property var blurRegions: []

    // A 12x2 component-grid tile (1716x228). The built-in was screen-wide and
    // 240px tall: 2 rows (228) is the nearest vertical span, and 12 columns is
    // the widest span the grid allows, so it stays close to full-bleed on a
    // 1080p display. The host (PluginWidget) sizes us from the manifest `grid`
    // and stretches this root to fill it; the implicit size is only a fallback
    // for standalone use. See docs/widget-grid.md.
    implicitWidth: Appearance.sizes.widgetGridSpanX(12)
    implicitHeight: Appearance.sizes.widgetGridSpanY(2)
    anchors.fill: parent

    readonly property list<real> points: GlobalStates.visualizerPoints

    property real barWidth: 4
    property real barSpacing: Appearance.spacing.space100
    // Fill the tile, leaving the same headroom the built-in kept above its
    // tallest bar. At the default scale this is exactly the old 220px.
    property real maxBarHeight: root.height > 0
        ? Math.max(1, root.height - Appearance.spacing.space100)
        : 220
    property real maxVisualizerValue: 1000
    property real smoothingDuration: 150

    // Bar count follows the widget's own width now that the host, not the
    // screen, decides how wide the visualiser is.
    readonly property int barCount: Math.max(1, Math.floor(root.width / (barWidth + barSpacing)))

    readonly property var smoothedPoints: {
        let raw = points
        if (!raw || raw.length === 0) return Array(barCount).fill(0)
        let count = barCount
        let mapped = new Array(count)
        let rawLenM1 = raw.length - 1

        for (let i = 0; i < count; i++) {
            let progress = i / (count - 1 || 1)
            let relPos = progress * rawLenM1
            let low = Math.floor(relPos)
            let high = Math.ceil(relPos)
            let mix = relPos - low
            mapped[i] = (raw[low] * (1 - mix)) + (raw[high] * (high < raw.length ? mix : 0))
        }

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
                    const v = root.smoothedPoints[index] ?? 0
                    return Math.max(root.barWidth, (v / root.maxVisualizerValue) * root.maxBarHeight)
                }
                height: pointValue
                topLeftRadius: root.barWidth / 2
                topRightRadius: root.barWidth / 2
                anchors.bottom: parent.bottom

                property real intensity: pointValue / root.maxBarHeight
                color: Qt.rgba(
                    Appearance.colors.colPrimary.r * intensity + Appearance.colors.colPrimaryContainer.r * (1 - intensity),
                    Appearance.colors.colPrimary.g * intensity + Appearance.colors.colPrimaryContainer.g * (1 - intensity),
                    Appearance.colors.colPrimary.b * intensity + Appearance.colors.colPrimaryContainer.b * (1 - intensity),
                    1
                )

                Behavior on height {
                    NumberAnimation { duration: root.smoothingDuration; easing.type: Easing.OutQuad }
                }
            }
        }
    }
}
