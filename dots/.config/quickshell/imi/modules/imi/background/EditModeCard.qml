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

    // ---- the glass edge ---------------------------------------------------
    //
    // The card used to end at a 1px colLayer0Border line, which is the shell's
    // outline for a floating surface and is right for a panel sitting on a
    // surface this file's own tokens were derived from. Over a WALLPAPER it is
    // a drawn line rather than an edge: measured on this library's darkest
    // picture the outline came back at 27/255 with the desktop at 0 inside it
    // and the blurred backdrop at 12 outside, so the whole boundary was ten
    // levels of contrast wide and read as a seam in a screenshot.
    //
    // What replaces it is a bevel with THICKNESS, in three tones, and the
    // reason it is three is that no single one survives every wallpaper:
    //
    //   - a shade band just OUTSIDE the card, so the card has a lip. It is what
    //     carries the edge over a bright picture, where a specular cannot.
    //   - a specular ON the edge, brightest along the top and fading down the
    //     sides to a weak bounce at the bottom - the same lamp the drop shadow
    //     below is drawn for. A uniform bright rim reads as a stroke; a rim that
    //     is brighter where light would catch reads as a surface.
    //   - a highlight just INSIDE, which is what gives the specular something to
    //     be the outer face of rather than a line floating on the seam.
    //
    // The first two cost nothing extra: they are plain Rectangles declared
    // inside `surround`, whose layer is already masked to the complement of the
    // card - so the mask cuts each of them down to the band outside the card by
    // itself, and the gradient that shades them is the Rectangle's own. No
    // second layer, no second mask, and nothing re-rendering the backdrop, which
    // is the cost this whole component is arranged to avoid.
    readonly property real edgeShadeWidth: Appearance.borderWidth.heavy
    readonly property real edgeSpecularWidth: Appearance.borderWidth.emphasis

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

        // Drawn AFTER the shadow, because the shadow is at its darkest exactly
        // where these two are: a bright line standing on the near edge of a
        // pool of shade is the whole of what reads as glass, and a shadow drawn
        // over it would be a shadow of the card cast onto the card's own rim.
        //
        // Both are grown from the card and cut back to it by `surround`'s mask,
        // so their inner boundary IS the card's edge - to the same antialiased
        // pixel as the corner, because it is the same mask that makes the
        // corner.
        Rectangle {
            id: edgeShade
            x: root.card.x - root.edgeShadeWidth
            y: root.card.y - root.edgeShadeWidth
            width: root.card.width + 2 * root.edgeShadeWidth
            height: root.card.height + 2 * root.edgeShadeWidth
            radius: root.cardRadius > 0 ? root.cardRadius + root.edgeShadeWidth : 0
            antialiasing: true
            // Weakest where the light is and strongest opposite it. Note the
            // far stops are the shade's own colour at zero alpha rather than
            // "transparent": a stop interpolating toward #00000000 walks the
            // colour through black, which is the smudge WidgetCanvas's lattice
            // fade already records - here it would be a second, wider shade.
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Appearance.colors.colGlassShade, 0.18) }
                GradientStop { position: 1; color: Qt.alpha(Appearance.colors.colGlassShade, 0.5) }
            }
        }

        Rectangle {
            id: edgeSpecular
            x: root.card.x - root.edgeSpecularWidth
            y: root.card.y - root.edgeSpecularWidth
            width: root.card.width + 2 * root.edgeSpecularWidth
            height: root.card.height + 2 * root.edgeSpecularWidth
            radius: root.cardRadius > 0 ? root.cardRadius + root.edgeSpecularWidth : 0
            antialiasing: true
            // The non-uniformity is the point. A rim at one strength all the way
            // round is a stroke however bright it is; light catching the top of
            // an edge, fading off down the sides and coming back weakly at the
            // bottom is what a piece of glass looks like. The bottom stop is a
            // bounce off whatever the card is lying on, so it is much weaker
            // than the top rather than symmetric with it.
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Appearance.colors.colGlassSpecular, 0.55) }
                GradientStop { position: 0.5; color: Qt.alpha(Appearance.colors.colGlassSpecular, 0.18) }
                GradientStop { position: 1; color: Qt.alpha(Appearance.colors.colGlassSpecular, 0.3) }
            }
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

    // The inner face of the bevel. This one cannot ride `surround`'s mask - it
    // is INSIDE the card, which is exactly what that mask removes - so it is a
    // border rather than a gradient-filled rect, and it is uniform. That is a
    // deliberate asymmetry rather than an omission: the specular is the tone
    // that has to look lit, and this is the tone that has to make the specular
    // look like the outside of something. Faint enough that it does not become
    // a second line on a dark wallpaper, present enough that the edge has a
    // near side.
    Rectangle {
        id: cardInnerHighlight
        x: root.card.x + Appearance.borderWidth.standard
        y: root.card.y + Appearance.borderWidth.standard
        width: root.card.width - 2 * Appearance.borderWidth.standard
        height: root.card.height - 2 * Appearance.borderWidth.standard
        radius: Math.max(0, root.cardRadius - Appearance.borderWidth.standard)
        color: "transparent"
        antialiasing: true
        border.width: Appearance.borderWidth.standard
        border.color: Qt.alpha(Appearance.colors.colGlassSpecular, 0.14)
    }
}
