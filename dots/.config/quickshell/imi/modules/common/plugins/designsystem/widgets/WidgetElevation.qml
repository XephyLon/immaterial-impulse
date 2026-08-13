import QtQuick
import QtQuick.Effects
import qs.modules.common
import "../../resize-tension.js" as Tension

// The one shadow a desktop widget casts.
//
// `WidgetCard` owned this along with the card surface, which served the four
// widgets that are cards. Five older bundled widgets are not cards and never
// could be - a cookie dial, a punched glyph grid, a shape-masked image, and a
// card with an avatar bubble straddling its top edge - and each carried its
// own `StyledDropShadow` at its own radius, colour and alpha. So the elevation
// is the piece that moves out: wrap whatever a widget actually paints and it
// casts the tuned shadow (`Appearance.elevation`, picked on the real wallpaper
// in ShadowTuningPlayground), lifts on hover and further on drag, and drops
// the shadow while it is moving.
//
// The shadow follows PAINTED ALPHA, which is the point: a rounded card, a
// twelve-lobed cookie and a Heart-masked photograph all cast the shape they
// actually draw. It follows from that where this belongs in a widget - around
// the BODY, never around a whole widget whose labels and glyphs would each
// cast one too.
//
// The frame carrying the layer is inset NEGATIVELY, because a layer clips at
// its item's bounds and both the shadow and the card's elastic resize bow are
// drawn outside them. Children still see this item's own box: the bleed is
// added on the frame and taken straight back off the body, so no call site
// compensates for it.
Item {
    id: root

    default property alias data: body.data

    property bool shadowEnabled: true
    property bool dragging: false
    property bool hovered: bodyHover.hovered
    // Motion drops the shadow and it returns on settle, exactly as the frost
    // does: re-rendering a blurred copy of the body every frame of a morph is
    // the expensive path, and the body is moving too fast to read a shadow.
    property bool motionActive: false
    readonly property bool shadowVisible: root.shadowEnabled && !root.motionActive

    property real bleed: Tension.BOW_PX * 2

    property real lift: root.dragging ? Appearance.elevation.dragLift
        : (root.hovered ? Appearance.elevation.hoverLift : 1.0)
    Behavior on lift {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }

    Item {
        id: shadowFrame
        anchors.fill: parent
        anchors.margins: -root.bleed

        layer.enabled: root.shadowVisible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: Appearance.elevation.blur * root.lift
            shadowOpacity: Appearance.elevation.shadowOpacity
            shadowVerticalOffset: Appearance.elevation.offsetY * root.lift
            shadowHorizontalOffset: 0
            shadowScale: Appearance.elevation.shadowScale
            shadowColor: Appearance.elevation.shadowColor
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: root.bleed

            // State only, no cursor: the cursor is a different channel and two
            // handlers arguing over it is a bug this repo has already paid for.
            HoverHandler {
                id: bodyHover
            }
        }
    }
}
