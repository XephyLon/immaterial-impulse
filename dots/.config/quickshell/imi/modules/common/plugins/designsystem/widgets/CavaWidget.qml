import QtQuick
import qs.services
import "../services"
import "../../../functions/cavaBands.js" as CavaBands
import qs.modules.common

Canvas {
    id: root

    property color barColor: Appearance.m3colors.m3primary
    property int maxHeight: 40 * Appearance.effectiveScale
    property int barCount: CavaService.barCount
    property real barSpacing: 2 * Appearance.effectiveScale

    readonly property real barWidth: Math.max(1, (width - (barSpacing * (barCount - 1))) / barCount)
    height: maxHeight

    property var _heights: []
    property var _targets: []
    property real _smoothing: 0.35

    function _initArrays(count) {
        var arr = []
        for (var i = 0; i < count; i++) arr.push(0)
        root._heights = arr
        root._targets = arr.slice()
    }

    onBarCountChanged: root._initArrays(barCount)

    Component.onCompleted: root._initArrays(barCount)

    // Bands nobody is looking at still cost a running cava and a repaint per
    // spectrum, so the claim follows what is actually drawn. `visible` is the
    // effective value, so an ancestor switching off is enough - no consumer has
    // to know which ancestor, or why.
    CavaRef { active: root.visible }

    Connections {
        target: CavaService
        function onValuesChanged() {
            // The producer's band count is not this widget's: reshape rather
            // than reading the first `barCount` of them, which left every bar
            // past the producer's count frozen and, at a lower count, hid the
            // top of the spectrum entirely.
            var levels = CavaBands.bands(CavaService.values, root.barCount, CavaService.maxValue)
            var t = root._targets
            for (var i = 0; i < root.barCount; i++)
                t[i] = Math.min(root.maxHeight, Math.max(1.5 * Appearance.effectiveScale, levels[i] * root.maxHeight))
        }
    }

    Timer {
        interval: 16
        running: root.visible && CavaService.active
        repeat: true
        onTriggered: {
            var h = root._heights
            var t = root._targets
            var changed = false
            var n = Math.min(root.barCount, t.length)
            for (var i = 0; i < n; i++) {
                var diff = t[i] - h[i]
                if (Math.abs(diff) > 0.5) {
                    h[i] += diff * root._smoothing
                    changed = true
                } else {
                    h[i] = t[i]
                }
            }
            if (changed) root.requestPaint()
        }
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        var bw = root.barWidth
        var bs = root.barSpacing
        var cols = root._heights
        var color = root.barColor
        var ch = height

        ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 1.0)

        for (var i = 0; i < root.barCount && i < cols.length; i++) {
            var bh = cols[i]
            var x = i * (bw + bs)
            var y = ch - bh
            var r = Math.min(2 * Appearance.effectiveScale, bw / 2)

            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.lineTo(x + bw - r, y)
            ctx.arcTo(x + bw, y, x + bw, y + r, r)
            ctx.lineTo(x + bw, y + bh - r)
            ctx.arcTo(x + bw, y + bh, x + bw - r, y + bh, r)
            ctx.lineTo(x + r, y + bh)
            ctx.arcTo(x, y + bh, x, y + bh - r, r)
            ctx.lineTo(x, y + r)
            ctx.arcTo(x, y, x + r, y, r)
            ctx.closePath()
            ctx.fill()
        }
    }
}
