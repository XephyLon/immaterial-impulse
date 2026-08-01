import QtQuick
import qs.modules.common

Canvas {
    id: root
    property color color: "#ffffff"
    property int dashLength: 6 * Appearance.effectiveScale
    property int gapLength: 4 * Appearance.effectiveScale
    property int borderWidth: Math.max(1, 1 * Appearance.effectiveScale)

    onDashLengthChanged: requestPaint()
    onGapLengthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        ctx.save();
        ctx.strokeStyle = root.color;
        ctx.lineWidth = root.borderWidth;
        if (root.gapLength > 0) {
            ctx.setLineDash([root.dashLength, root.gapLength]); // Set dash pattern
        }
        ctx.strokeRect(root.borderWidth / 2, root.borderWidth / 2, width - root.borderWidth, height - root.borderWidth); // Draw it
        ctx.restore();
    }
}
