import QtQuick
import QtQuick.Shapes
import qs.modules.common

/**
 * The one open state a bar widget has while its popup is up.
 *
 * A dashed outline in the primary colour around the widget, in the widget's
 * own rounding. It says "anchored here" without repainting the widget: a
 * tonal container behind a bar widget that has none broke every style but
 * M3 (measured on the Docker gauge: a filled pill behind a bare ring). The
 * dashes tile the perimeter in whole counts, so there is no half dash at
 * the seam, and the outline is scene-graph geometry rather than a Canvas,
 * which would be a GUI-thread raster on every frame it moves.
 *
 * It is never snapped in or out: one presence scalar fades it on the
 * effects tier, and on the same clock the dashes march forward on the way
 * in and back on the way out (a spatial tier, one for both directions,
 * because the state is reversible). Fill the widget with it and bind
 * `shown` to the popup's open state.
 */
Item {
    id: root

    property bool shown: false
    property real radius: Appearance.rounding.full
    property color color: Appearance.colors.colPrimary
    property real strokeWidth: Appearance.borderWidth.standard
    property real dashLength: Appearance.spacing.space75
    property real gapLength: Appearance.spacing.space50
    // How far the dashes travel on the way in, in dash patterns.
    property real marchPatterns: 2

    property real presence: root.shown ? 1 : 0
    Behavior on presence {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    property real march: root.shown ? 1 : 0
    Behavior on march {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    opacity: root.presence
    visible: root.presence > 0

    // Geometry, all in pixels. The stroke is centred on the path, so the
    // path sits half a stroke inside the widget's edge.
    readonly property real inset: root.strokeWidth / 2
    readonly property real cornerRadius: Math.max(0, Math.min(root.radius,
        (Math.min(root.width, root.height) - root.strokeWidth) / 2))
    readonly property real straightWidth: Math.max(0, root.width - root.strokeWidth - root.cornerRadius * 2)
    readonly property real straightHeight: Math.max(0, root.height - root.strokeWidth - root.cornerRadius * 2)
    readonly property real perimeter: 2 * (root.straightWidth + root.straightHeight) + 2 * Math.PI * root.cornerRadius
    readonly property real patternLength: Math.max(0.001, root.dashLength + root.gapLength)
    readonly property int patternRepeats: Math.max(1, Math.round(root.perimeter / root.patternLength))
    // Stretches the pattern so a whole number of them closes the loop.
    readonly property real patternScale: root.perimeter > root.patternLength
        ? root.perimeter / (root.patternRepeats * root.patternLength) : 1
    // ShapePath measures dashes and their offset in stroke widths.
    readonly property real strokeUnit: Math.max(0.001, root.strokeWidth)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: root.strokeWidth
            strokeStyle: root.gapLength > 0 ? ShapePath.DashLine : ShapePath.SolidLine
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin
            dashPattern: [
                Math.max(0.001, root.dashLength * root.patternScale / root.strokeUnit),
                Math.max(0.001, root.gapLength * root.patternScale / root.strokeUnit)
            ]
            dashOffset: -root.march * root.marchPatterns * root.patternLength * root.patternScale / root.strokeUnit

            startX: root.inset + root.cornerRadius
            startY: root.inset
            PathLine { x: root.width - root.inset - root.cornerRadius; y: root.inset }
            PathArc { x: root.width - root.inset; y: root.inset + root.cornerRadius; radiusX: root.cornerRadius; radiusY: root.cornerRadius }
            PathLine { x: root.width - root.inset; y: root.height - root.inset - root.cornerRadius }
            PathArc { x: root.width - root.inset - root.cornerRadius; y: root.height - root.inset; radiusX: root.cornerRadius; radiusY: root.cornerRadius }
            PathLine { x: root.inset + root.cornerRadius; y: root.height - root.inset }
            PathArc { x: root.inset; y: root.height - root.inset - root.cornerRadius; radiusX: root.cornerRadius; radiusY: root.cornerRadius }
            PathLine { x: root.inset; y: root.inset + root.cornerRadius }
            PathArc { x: root.inset + root.cornerRadius; y: root.inset; radiusX: root.cornerRadius; radiusY: root.cornerRadius }
        }
    }
}
