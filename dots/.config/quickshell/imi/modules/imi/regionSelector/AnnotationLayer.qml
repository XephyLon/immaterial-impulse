import qs.modules.common
import QtQuick

/**
 * Freehand/shape annotations over the frozen screenshot, in region-local
 * coordinates. Shapes are plain objects; the Canvas repaints the committed
 * list plus the one being dragged. Rendering is resolution-independent so
 * the same paint routine draws the on-screen preview and the scaled
 * grabToImage composite.
 */
Item {
    id: layer

    property string tool: "pen" // pen | arrow | rect | ellipse
    property color strokeColor: "#ff5252"
    property real strokeWidth: 4
    property var shapes: []
    property var currentShape: null
    readonly property bool hasAnnotations: shapes.length > 0

    function undo() {
        if (layer.shapes.length === 0) return;
        layer.shapes = layer.shapes.slice(0, -1);
        canvas.requestPaint();
    }

    function clearAll() {
        layer.shapes = [];
        layer.currentShape = null;
        canvas.requestPaint();
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        function paintShape(ctx, s) {
            ctx.strokeStyle = s.color;
            ctx.fillStyle = s.color;
            ctx.lineWidth = s.width;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            const x = Math.min(s.x1, s.x2), y = Math.min(s.y1, s.y2);
            const w = Math.abs(s.x2 - s.x1), h = Math.abs(s.y2 - s.y1);
            switch (s.type) {
            case "pen": {
                if (!s.points || s.points.length < 2) break;
                ctx.beginPath();
                ctx.moveTo(s.points[0].x, s.points[0].y);
                for (let i = 1; i < s.points.length; i++)
                    ctx.lineTo(s.points[i].x, s.points[i].y);
                ctx.stroke();
                break;
            }
            case "rect":
                ctx.strokeRect(x, y, w, h);
                break;
            case "ellipse": {
                // Qt's Canvas lacks ctx.ellipse(); scale a unit circle.
                if (w < 1 || h < 1) break;
                ctx.save();
                ctx.translate(x + w / 2, y + h / 2);
                ctx.scale(w / 2, h / 2);
                ctx.lineWidth = s.width / Math.max(w, h) * 2;
                ctx.beginPath();
                ctx.arc(0, 0, 1, 0, 2 * Math.PI);
                ctx.restore();
                // Stroke AFTER restore so line width is in surface pixels.
                ctx.lineWidth = s.width;
                ctx.stroke();
                break;
            }
            case "arrow": {
                const angle = Math.atan2(s.y2 - s.y1, s.x2 - s.x1);
                const headLength = Math.max(10, s.width * 3.5);
                // Shorten the shaft so it doesn't poke through the head.
                const shaftX = s.x2 - headLength * 0.6 * Math.cos(angle);
                const shaftY = s.y2 - headLength * 0.6 * Math.sin(angle);
                ctx.beginPath();
                ctx.moveTo(s.x1, s.y1);
                ctx.lineTo(shaftX, shaftY);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(s.x2, s.y2);
                ctx.lineTo(s.x2 - headLength * Math.cos(angle - Math.PI / 6),
                           s.y2 - headLength * Math.sin(angle - Math.PI / 6));
                ctx.lineTo(s.x2 - headLength * Math.cos(angle + Math.PI / 6),
                           s.y2 - headLength * Math.sin(angle + Math.PI / 6));
                ctx.closePath();
                ctx.fill();
                break;
            }
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            for (const s of layer.shapes)
                paintShape(ctx, s);
            if (layer.currentShape)
                paintShape(ctx, layer.currentShape);
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        acceptedButtons: Qt.LeftButton

        onPressed: mouse => {
            layer.currentShape = {
                type: layer.tool,
                color: String(layer.strokeColor),
                width: layer.strokeWidth,
                x1: mouse.x, y1: mouse.y, x2: mouse.x, y2: mouse.y,
                points: [{ x: mouse.x, y: mouse.y }]
            };
            canvas.requestPaint();
        }
        onPositionChanged: mouse => {
            if (!layer.currentShape) return;
            const s = layer.currentShape;
            s.x2 = mouse.x;
            s.y2 = mouse.y;
            if (layer.tool === "pen")
                s.points.push({ x: mouse.x, y: mouse.y });
            layer.currentShape = s;
            canvas.requestPaint();
        }
        onReleased: {
            const s = layer.currentShape;
            layer.currentShape = null;
            if (!s) return;
            const moved = Math.abs(s.x2 - s.x1) + Math.abs(s.y2 - s.y1) > 3
                || (s.points && s.points.length > 3);
            if (moved)
                layer.shapes = layer.shapes.concat([s]);
            canvas.requestPaint();
        }
    }
}
