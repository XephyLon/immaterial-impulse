import QtQuick
import qs.modules.common
import qs.modules.common.functions

/*
 * Simple one value line graph
 */
Canvas {
    id: root

    enum Alignment { Left, Right }

    required property list<real> values
    property int points: values.length
    property color color: Appearance.colors.colPrimary
    property real fillOpacity: 0.5
    property var alignment: Graph.Alignment.Left
    // How much of the graph is drawn, left to right, as a fraction. Opt in to
    // `animateReveal` and each new set of values draws itself in on the
    // element-move tier instead of appearing whole; a live graph that is
    // repainted per sample (the resources overlay) leaves it off.
    property real reveal: 1
    property bool animateReveal: false

    NumberAnimation {
        id: revealAnimation
        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
    }

    // Drawn in on new values AND on coming into view: the results graph's
    // samples arrive one per second while the score is still hidden, so a
    // draw-in keyed on values alone has finished before anyone can see it.
    // `visible` is effective visibility, so a Presence fading the parent in
    // is what starts it.
    function drawIn() {
        if (root.animateReveal && root.visible && root.values && root.values.length >= 2)
            revealAnimation.restart()
    }
    onRevealChanged: root.requestPaint()
    onVisibleChanged: root.drawIn()
    onValuesChanged: {
        root.drawIn()
        root.requestPaint()
    }
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!root.values || root.values.length < 2)
            return
        // The reveal is a clip, not a shorter path: the drawn part is exactly
        // what the finished graph shows there, so nothing re-shapes as it lands.
        // Saved and restored around the paint, because a Canvas context keeps
        // its clip between paints and clips only ever intersect - without the
        // restore the first narrow frame would cap every frame after it.
        ctx.save()
        ctx.beginPath()
        ctx.rect(0, 0, width * Math.max(0, Math.min(1, root.reveal)), height)
        ctx.clip()

        var n = root.points
        var dx = width / (n - 1)
        ctx.strokeStyle = root.color
        ctx.fillStyle = ColorUtils.transparentize(root.color, 1 - root.fillOpacity)
        ctx.lineWidth = 2
        ctx.beginPath()
        for (var i = 0; i < n; ++i) {
            var valueIndex = (root.alignment === Graph.Alignment.Right) ? root.values.length - n + i : i
            if (valueIndex < 0 || valueIndex >= root.values.length) {
                continue; // No data for this point
            }
            var x = i * dx
            var norm = root.values[valueIndex] // already in 0-1 range
            var y = height - norm * height
            if (valueIndex === 0) {
                ctx.moveTo(x, height)
                ctx.lineTo(x, y)
            } else {
                ctx.lineTo(x, y)
            }
        }
        ctx.stroke()
        ctx.lineTo(width, height)
        ctx.fill()
        ctx.restore()
    }
}
