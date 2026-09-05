import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Effects

Canvas { // Visualizer
    id: root
    property list<var> points
    property list<var> smoothPoints
    property real maxVisualizerValue: 1000
    property int smoothing: 2
    property bool live: true
    property color color: Appearance.m3colors.m3primary

    onPointsChanged: () => {
        root.requestPaint()
    }

    anchors.fill: parent
    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        var points = root.points;
        var maxVal = root.maxVisualizerValue || 1;
        var h = height;
        var w = width;
        var n = points.length;
        if (n < 2) return;

        // Smoothing: simple moving average (optional). Reuse the buffer across
        // paints - reallocating it every frame (this runs at ~display rate per
        // visible visualizer) churned the GC for nothing; only the band count
        // changing needs a new array.
        var smoothWindow = root.smoothing; // adjust for more/less smoothing
        var sp = root.smoothPoints;
        // Fill BEFORE assigning on the resize path: assigning first copies the
        // still-empty array into the property, and the writes that follow land
        // in the detached local - one blank frame per band-count change. The
        // steady-state reuse writes through the wrapper, as push always did.
        var fresh = sp.length !== n;
        if (fresh) sp = new Array(n);
        for (var i = 0; i < n; ++i) {
            var sum = 0, count = 0;
            for (var j = -smoothWindow; j <= smoothWindow; ++j) {
                var idx = Math.max(0, Math.min(n - 1, i + j));
                sum += points[idx];
                count++;
            }
            sp[i] = root.live ? sum / count : 0; // not playing -> flat line
        }
        if (fresh) root.smoothPoints = sp;

        ctx.beginPath();
        ctx.moveTo(0, h);
        for (var i = 0; i < n; ++i) {
            var x = i * w / (n - 1);
            var y = h - (root.smoothPoints[i] / maxVal) * h;
            ctx.lineTo(x, y);
        }
        ctx.lineTo(w, h);
        ctx.closePath();

        ctx.fillStyle = Qt.rgba(
            root.color.r,
            root.color.g,
            root.color.b,
            0.15
        );
        ctx.fill();
    }

    layer.enabled: true
    layer.effect: MultiEffect { // Blur a bit to obscure away the points
        source: root
        saturation: 0.2
        blurEnabled: true
        blurMax: 7
        blur: 1
    }
}