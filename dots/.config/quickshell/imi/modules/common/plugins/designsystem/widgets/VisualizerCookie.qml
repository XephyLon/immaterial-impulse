import QtQuick
import "./shapes/rounded-polygon.js" as RoundedPolygon
import "./shapes/corner-rounding.js" as CornerRounding

// A Material cookie whose lobes each answer to their own level, so the outline
// ripples per frequency band instead of breathing as one shape.
Item {
    id: root

    property int lobes: 12
    // 0..1, one per lobe, lobe 0 at 3 o'clock and travelling clockwise.
    property list<real> levels: []
    property real baseRadius: 0.8
    property real reach: 0.14
    property color color: "#685496"
    property int implicitSize: 100

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    // The rounding the Material cookies are cut with (material-shapes.js).
    readonly property var cornerRounding: new CornerRounding.CornerRounding(0.5)
    property var polygon: null

    function lobeRadii(): var {
        const radii = [];
        for (let i = 0; i < root.lobes; i++) {
            const level = i < root.levels.length ? Math.max(0, Math.min(1, root.levels[i])) : 0;
            radii.push(root.baseRadius + level * root.reach);
        }
        return radii;
    }

    function rebuild() {
        root.polygon = RoundedPolygon.RoundedPolygon.starPerLobe(root.lobes, 1, lobeRadii(), root.cornerRounding);
        canvas.requestPaint();
    }

    onLevelsChanged: rebuild()
    onLobesChanged: rebuild()
    onBaseRadiusChanged: rebuild()
    onReachChanged: rebuild()
    Component.onCompleted: rebuild()

    // Not ShapeCanvas: that builds a Morph and runs a 350ms transition on every
    // polygon change, and a Morph of this shape measures ~1.3ms to construct -
    // a shape rebuilt per frame would spend more time matching features than
    // drawing, and would never reach the shape it was morphing to. The polygon
    // is drawn at a fixed scale rather than normalized() for the same class of
    // reason: normalizing refits every frame, so a lobe pushing out would
    // shrink the other eleven instead of standing out.
    Canvas {
        id: canvas
        anchors.fill: parent

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (!root.polygon)
                return;
            const cubics = root.polygon.cubics;
            if (cubics.length === 0)
                return;

            ctx.save();
            ctx.translate(width / 2, height / 2);
            const scale = Math.min(width, height) / 2;
            ctx.scale(scale, scale);
            ctx.beginPath();
            ctx.moveTo(cubics[0].anchor0X, cubics[0].anchor0Y);
            for (const cubic of cubics)
                ctx.bezierCurveTo(cubic.control0X, cubic.control0Y, cubic.control1X, cubic.control1Y, cubic.anchor1X, cubic.anchor1Y);
            ctx.closePath();
            ctx.fillStyle = root.color;
            ctx.fill();
            ctx.restore();
        }
    }

    onColorChanged: canvas.requestPaint()
}
