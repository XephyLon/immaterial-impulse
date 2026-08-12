import QtQuick
import "./morph.js" as Morph
import "./shape-fit.js" as ShapeFit

Canvas {
    id: root
    property color color: "#685496"
    property var roundedPolygon: null
    property bool polygonIsNormalized: true
    property real borderWidth: 0
    property color borderColor: "transparent"

    // Fill the whole item rather than the largest square inside it.
    //
    // The default is the square: a normalised polygon is scaled by
    // `min(width, height)` and centred, which is right for a glyph, a button or
    // anything else that is as tall as it is wide. A *card* is not - at 320x112
    // the default draws a 112x112 shape floating in the middle of it - so a
    // shape can only be a card's outline if it may stretch to the box it is
    // given. Off by default because every existing caller wants the square.
    property bool stretch: false

    // Internals: size
    property var bounds: roundedPolygon.calculateBounds()
    implicitWidth: bounds[2] - bounds[0]
    implicitHeight: bounds[3] - bounds[1]

    // Internals: anim
    property var prevRoundedPolygon: null
    property double progress: 1
    property var morph: new Morph.Morph(roundedPolygon, roundedPolygon)
    property Animation animation: NumberAnimation {
        duration: 350
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.42, 1.67, 0.21, 0.90, 1, 1] // Material 3 Expressive fast spatial (https://m3.material.io/styles/motion/overview/specs)
    }
    
    onRoundedPolygonChanged: {
        delete root.morph
        root.morph = new Morph.Morph(root.prevRoundedPolygon ?? root.roundedPolygon, root.roundedPolygon)
        morphBehavior.enabled = false;
        root.progress = 0
        morphBehavior.enabled = true;
        root.progress = 1
        root.prevRoundedPolygon = root.roundedPolygon
    }

    Behavior on progress {
        id: morphBehavior
        animation: root.animation
    }

    // A Canvas repaints on resize and on nothing else, so every input onPaint
    // reads has to be mirrored here or it is the silent half - the shape keeps
    // the last values it happened to be drawn with.
    onProgressChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onStretchChanged: requestPaint()
    onBorderWidthChanged: requestPaint()
    onBorderColorChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.fillStyle = root.color
        ctx.clearRect(0, 0, width, height)
        if (!root.morph) return
        const cubics = root.morph.asCubics(root.progress)
        if (cubics.length === 0) return

        // Placement and the pixel mapping live in shape-fit.js - see there for
        // why the path is built in pixels rather than drawn through ctx.scale().
        const placement = ShapeFit.fit(root.width, root.height,
            root.polygonIsNormalized, root.stretch)
        const mapX = value => ShapeFit.mapX(value, placement)
        const mapY = value => ShapeFit.mapY(value, placement)

        ctx.beginPath()
        ctx.moveTo(mapX(cubics[0].anchor0X), mapY(cubics[0].anchor0Y))
        for (const cubic of cubics) {
            ctx.bezierCurveTo(
                mapX(cubic.control0X), mapY(cubic.control0Y),
                mapX(cubic.control1X), mapY(cubic.control1Y),
                mapX(cubic.anchor1X), mapY(cubic.anchor1Y)
            )
        }
        ctx.closePath()
        ctx.fill()
        if (root.borderWidth > 0) {
            ctx.strokeStyle = root.borderColor
            ctx.lineWidth = root.borderWidth
            ctx.stroke()
        }
    }
}
