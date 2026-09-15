import QtQuick
import qs.modules.common
import qs.modules.common.functions

Canvas {
    id: root
    property color color: "#ffffff"
    property int dashLength: 6
    property int gapLength: 4
    property int borderWidth: 1
    // Corner radius of the dashed outline, so it can trace a rounded control
    // instead of boxing it in a square (0 = the plain rectangle it drew before).
    property real radius: 0

    onDashLengthChanged: requestPaint()
    onGapLengthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onRadiusChanged: requestPaint()
    onColorChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        ctx.save();
        ctx.strokeStyle = root.color;
        ctx.lineWidth = root.borderWidth;
        if (root.gapLength > 0) {
            ctx.setLineDash([root.dashLength, root.gapLength]); // Set dash pattern
        }
        const x = root.borderWidth / 2, y = root.borderWidth / 2;
        const w = width - root.borderWidth, h = height - root.borderWidth;
        const r = Math.max(0, Math.min(root.radius, w / 2, h / 2));
        if (r <= 0) {
            ctx.strokeRect(x, y, w, h);
        } else {
            ctx.beginPath();
            ctx.moveTo(x + r, y);
            ctx.lineTo(x + w - r, y);
            ctx.arcTo(x + w, y, x + w, y + r, r);
            ctx.lineTo(x + w, y + h - r);
            ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
            ctx.lineTo(x + r, y + h);
            ctx.arcTo(x, y + h, x, y + h - r, r);
            ctx.lineTo(x, y + r);
            ctx.arcTo(x, y, x + r, y, r);
            ctx.closePath();
            ctx.stroke();
        }
        ctx.restore();
    }
}
