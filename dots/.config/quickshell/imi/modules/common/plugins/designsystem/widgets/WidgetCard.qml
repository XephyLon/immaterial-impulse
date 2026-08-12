import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions as Functions
import "./shapes"

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

    Rectangle {
        id: rectSurface
        visible: !root.usesShapeCanvas
        anchors.fill: parent
        radius: root.radius
        color: root.effectiveColor
    }

    Loader {
        active: root.usesShapeCanvas
        anchors.fill: parent
        sourceComponent: MaterialShape {
            shapeString: root.shapeName
            color: root.effectiveColor
            stretch: true
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
