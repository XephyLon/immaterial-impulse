import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions as Functions
import "./shapes"
import "../../resize-tension.js" as Tension

// The surface a desktop widget draws itself on.
//
// Before this existed, each widget declared its own: DesktopWeatherWidget,
// DesktopCurrencyWidget and nandoroid-media's LayoutCookie carried three
// byte-identical `Rectangle { radius: 30 * effectiveScale; color: blur ?
// applyAlpha(tint, opacity) : tint }` blocks, and calendar's copy had already
// drifted to a different rounding token and colour source - which is the
// argument for the component: with four copies, container motion means tuning
// it four times and getting four slightly different results.
//
// A widget composes zero, one or many of these (the system monitor has three
// and no outer container), so this is a *card*, not a widget container, and it
// deliberately does not own frost: `blurRegions` stays a widget-level
// declaration, for which `blurRegion` below is the per-card record.
//
// The shape is a parameter. Unset, the card is a plain Rectangle - the cheap
// path, and the only one the frost's OpacityMask can currently follow. Set to a
// MaterialShape name ("Squircle", "Ghostish", ...), the card is that polygon
// stretched to the card's box, drawn by the same ShapeCanvas the wallpaper
// shape picker morphs - so a card whose `shapeName` changes morphs for free.
Item {
    id: root

    // ---- the tint --------------------------------------------------------
    // The colour pair every copy spelled out: opaque tint normally, the same
    // tint thinned to `backgroundOpacity` when the widget frosts the wallpaper
    // behind it (the frost supplies the body, the tint only warms it).
    property color tint: Appearance.colors.colOnPrimary
    property bool useBlurBackground: false
    property real backgroundOpacity: 0.1
    readonly property color effectiveColor: root.useBlurBackground
        ? Functions.ColorUtils.applyAlpha(root.tint, root.backgroundOpacity)
        : root.tint

    // ---- the shape -------------------------------------------------------
    property real radius: 30 * Appearance.effectiveScale
    // Empty = rounded rectangle. A MaterialShape enum name = that polygon,
    // stretched to fill this card rather than squared inside it.
    property string shapeName: ""
    readonly property bool usesShapeCanvas: root.shapeName !== ""

    // ---- what the widget's blurRegions entry should say ------------------
    // One place builds the record, so a widget cannot disagree with its card
    // about where the frost goes. Radius is meaningless for a polygon card,
    // but the frost mask cannot follow a polygon yet either - that widget
    // should not frost this card until the mask learns shapes.
    readonly property var blurRegion: ({
        x: root.x, y: root.y, width: root.width, height: root.height,
        radius: root.radius
    })

    // ---- content ---------------------------------------------------------
    // Children land inside the card. With `clipContent` on they are cut at the
    // card's own outline (weather clips its split panels and slanted leaves
    // this way; it is also what cuts a 1x1 glyph hanging off the corner).
    default property alias data: contentItem.data
    property bool clipContent: false

    // ---- tension ---------------------------------------------------------
    // The bow the host's resize grip is applying, in pixels (resize-tension.js
    // owns the arithmetic). Zero at rest - and at rest the surface below is
    // the plain Rectangle, so a card that is never pulled never pays for a
    // Canvas. The clip mask deliberately stays the rounded rectangle: the bow
    // reaches at most BOW_PX outside the rect, and clipped content already
    // sits inside it.
    property real tensionX: 0
    property real tensionY: 0
    readonly property bool underTension: !root.usesShapeCanvas
        && (root.tensionX !== 0 || root.tensionY !== 0)

    // ---- elevation -------------------------------------------------------
    // The card casts a shadow, and lifts further the more directly it is
    // being handled: rest, hover, drag. The numbers are Appearance.elevation
    // (picked on the real wallpaper in ShadowTuningPlayground); what varies
    // here is only how far off the surface this card currently is.
    //
    // The shadow is taken from the BODY, not from the card as a whole - a
    // layer over the content would have every label and glyph casting one too.
    // It therefore follows painted alpha, which is the point: the plain
    // rectangle, the bowed canvas and a MaterialShape polygon all cast the
    // shape they actually draw.
    property bool shadowEnabled: true
    property bool dragging: false
    // Motion drops the shadow and it returns on settle, exactly as the frost
    // does: re-rendering a blurred copy of the body every frame of a morph is
    // the expensive path, and the card is moving too fast to read a shadow.
    property bool motionActive: root.underTension
    readonly property bool shadowVisible: root.shadowEnabled && !root.motionActive

    property real elevationLift: root.dragging ? Appearance.elevation.dragLift
        : (cardHover.hovered ? Appearance.elevation.hoverLift : 1.0)
    Behavior on elevationLift {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }

    // State only, no cursor: the cursor is a different channel and two
    // handlers arguing over it is a bug this repo has already paid for.
    HoverHandler { id: cardHover }

    // One frame around every body renderer, so one effect shadows all three.
    // It is inset NEGATIVELY by the bow's reach: a layer clips at its item's
    // bounds, and the bowed canvas deliberately draws outside the card.
    Item {
        id: bodySurface
        anchors.fill: parent
        anchors.margins: -Tension.BOW_PX * 2

        layer.enabled: root.shadowVisible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: Appearance.elevation.blur * root.elevationLift
            shadowOpacity: Appearance.elevation.shadowOpacity
            shadowVerticalOffset: Appearance.elevation.offsetY * root.elevationLift
            shadowHorizontalOffset: 0
            shadowScale: Appearance.elevation.shadowScale
            shadowColor: Appearance.elevation.shadowColor
        }

        Rectangle {
            id: rectSurface
            visible: !root.usesShapeCanvas && !root.underTension
            anchors.fill: parent
            anchors.margins: Tension.BOW_PX * 2
            radius: root.radius
            color: root.effectiveColor
        }

        // The bulged surface, alive only while pulled. Margins give the bow room
        // to draw outside the card's own box without being cut by the item.
        Loader {
            active: root.underTension
            anchors.fill: parent
            sourceComponent: Canvas {
                id: tensionCanvas
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const pad = Tension.BOW_PX * 2;
                    const radii = Tension.cornerRadii(root.radius, root.tensionX, root.tensionY);
                    const path = Tension.outline(root.width, root.height,
                        root.tensionX, root.tensionY, radii);
                    ctx.save();
                    ctx.translate(pad, pad);
                    ctx.fillStyle = root.effectiveColor;
                    ctx.beginPath();
                    for (const seg of path.segments) {
                        if (seg.op === "move") ctx.moveTo(seg.x, seg.y);
                        else if (seg.op === "line") ctx.lineTo(seg.x, seg.y);
                        else ctx.quadraticCurveTo(seg.cx, seg.cy, seg.x, seg.y);
                    }
                    ctx.closePath();
                    ctx.fill();
                    ctx.restore();
                }
                // A Canvas repaints on resize and nothing else - mirror every
                // input onPaint reads, or the shape keeps stale values.
                Connections {
                    target: root
                    function onTensionXChanged() { tensionCanvas.requestPaint(); }
                    function onTensionYChanged() { tensionCanvas.requestPaint(); }
                    function onEffectiveColorChanged() { tensionCanvas.requestPaint(); }
                }
            }
        }

        Loader {
            active: root.usesShapeCanvas
            anchors.fill: parent
            anchors.margins: Tension.BOW_PX * 2
            sourceComponent: MaterialShape {
                shapeString: root.shapeName
                color: root.effectiveColor
                stretch: true
            }
        }
    }

    Item {
        id: contentItem
        anchors.fill: parent
        layer.enabled: root.clipContent
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: root.width
                height: root.height
                radius: root.radius
            }
        }
    }
}
