import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

/**
 * Edit Mode's desktop, drawn as a card lifted off its own wallpaper.
 *
 * The mode shrinks the desktop with a transform and nothing else, which leaves
 * a hard rectangular edge with no corner, no border and no shadow - a cropped
 * screenshot rather than a surface being edited. This is the chrome around it:
 * the blurred backdrop, the corner, the drop shadow and the outline, as one
 * component so the four cannot end up a pixel apart from each other or from the
 * desktop. Everything geometric comes from `card`, which is
 * `edit_mode.js`'s `cardRect` - the same arithmetic the transform is built out
 * of - for the reason ClockDepthCutout is one component: a second copy of a
 * registration drifts, and the drift is invisible because both copies look
 * plausible.
 *
 * ---- why the backdrop is drawn ON TOP of the desktop -----------------------
 *
 * The desktop is three sibling items, each carrying the edit transform, and QML
 * has no rounded clip: there is no property on any of them that rounds a
 * corner, and wrapping all three in one masked layer means re-rendering the
 * wallpaper through an effect for every frame of the shrink.
 *
 * So the corner is made by covering it with what is behind it, which is this
 * same blurred picture. The backdrop draws above the desktop and is cut out to
 * the card's rounded rect, which is visually identical to drawing it behind
 * everywhere except the four corners - and at the corners it is the difference
 * between a rounded card and a square one. It also puts the shadow where a
 * shadow belongs: inside the same cut-out, over the backdrop, so only the half
 * of it outside the card survives and its interior never darkens the desktop it
 * is supposed to lift.
 *
 * What it costs is one full-screen layer and one mask, re-rendered while the
 * card's geometry moves - the 400ms of an entry or an exit, and never at rest.
 * The blur itself is not re-run for the chrome's sake: it is the same
 * WallpaperBlurBackdrop that was already being drawn, and it already re-renders
 * on a live Wallpaper Engine wallpaper whatever this does.
 */
Item {
    id: root

    // The wallpaper layer to blur - an item, never a path, so a
    // ShaderEffectSource renders it in its OWN coordinates and the backdrop
    // stays full-screen while the thing it samples is transformed.
    property Item wallpaperLayer: null
    property real blurRadius: 0
    property int blurSamples: 0
    // The desktop's rectangle on screen, and the corner it is drawn with. Both
    // interpolate from "the whole screen, square" so that at rest there is
    // nothing inset, nothing rounded and nothing to stand down.
    property rect card: Qt.rect(0, 0, root.width, root.height)
    property real cardRadius: 0

    // Everything that lives OUTSIDE the card, composited once and then cut to
    // shape. The mask is inverted, so what survives is the complement of the
    // card: the backdrop, and the outer half of the shadow drawn over it.
    Item {
        id: surround
        anchors.fill: parent

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: cardShapeMask
            invert: true
        }

        WallpaperBlurBackdrop {
            anchors.fill: parent
            source: root.wallpaperLayer
            radius: root.blurRadius
            samples: root.blurSamples
        }

        // Not drawn - it is the shape the shadow is taken from. A Rectangle
        // rather than an Item because StyledRectangularShadow reads its target's
        // radius, which is how the shadow's corner follows the card's.
        Rectangle {
            id: cardShape
            x: root.card.x
            y: root.card.y
            width: root.card.width
            height: root.card.height
            radius: root.cardRadius
            color: "transparent"
            visible: false
        }

        // The shell's one shadow for a floating surface, at the magnitude the
        // component defines. Measured against a 4403px card on a 5120px screen
        // before leaving it alone: raising `blur` from the component's 9 to 40
        // spreads the same total darkness over four times the distance and the
        // two renders are indistinguishable - the edge contrast is set by
        // `colShadow`'s alpha, not by the reach, and most of a RectangularShadow
        // sits UNDER its target, which the cut removes. A bigger number here
        // would have bought a different spelling and no depth.
        StyledRectangularShadow {
            target: cardShape
        }
    }

    // The cut. Its colour is an alpha channel rather than a colour - OpacityMask
    // reads nothing but alpha (AGENT.md's note on masking by alpha), so any
    // opaque value does, and a design token here would say something it does not
    // mean. `antialiasing` is what makes the corner smooth: the mask's own edge
    // is the card's edge.
    Item {
        id: cardShapeMask
        anchors.fill: parent
        visible: false

        Rectangle {
            x: root.card.x
            y: root.card.y
            width: root.card.width
            height: root.card.height
            radius: root.cardRadius
            color: "white"
            antialiasing: true
        }
    }

    // The 1px outline every floating surface in this shell carries beside its
    // shadow (docs/M3_GUIDELINES.md §1). Drawn over the seam between the
    // desktop and the cut rather than inside the mask, where the half of it
    // outside the card would be removed along with everything else there.
    Rectangle {
        id: cardEdge
        x: root.card.x
        y: root.card.y
        width: root.card.width
        height: root.card.height
        radius: root.cardRadius
        color: "transparent"
        antialiasing: true
        border.width: Appearance.borderWidth.standard
        border.color: Appearance.colors.colLayer0Border
    }
}
