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
 * the blurred backdrop, the corner, the drop shadow and the edge, as one
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
    // ONE tone, one pixel wide, and mostly not there. That is a correction of
    // this file's own previous answer rather than a tuning of it.
    //
    // The card used to end at a 1px colLayer0Border line, which is the shell's
    // outline for a floating surface and is right for a panel sitting on a
    // surface this file's own tokens were derived from. Over a WALLPAPER it is
    // a drawn line rather than an edge, so it was replaced by a bevel in three
    // tones: a 4px shade band outside the card, a 2px specular on the edge, and
    // a 1px highlight inside it. Each tone was defensible and the sum was a
    // BORDER - measured on the real desktop at 5120x1440, walking inward across
    // the left flank: backdrop 28, shade 17, 17, specular 77, 77, highlight
    // 128, desktop 105. Five drawn pixels of dark-then-bright piping, at one
    // strength the whole way round a 3872px card. Which is what "edit mode's
    // layout having this thick border is what looked ugly" names.
    //
    // What the three tones were each solving, and why none of them survives:
    //
    //   - the shade band gave the card a lip so the edge carried over a bright
    //     picture. `StyledRectangularShadow` below is already a darkening
    //     outside the card, from the same lamp, and it is the one the
    //     maintainer says is right. Two darkenings outside one edge is the
    //     shade band drawing a hard 2px copy of the soft one under it.
    //   - the inner highlight gave the specular a near side. It is a uniform
    //     line at the card's edge that composites over the DESKTOP, so it is
    //     the brightest thing on the boundary on three edges out of four (+24
    //     to +41 levels wherever it lands) - structurally the same object as
    //     the colLayer0Border outline removed in 1df616e62, in white.
    //   - the specular is the one that is really an edge: a catch where the
    //     light hits. It stays, at `standard` rather than `emphasis` width,
    //     and its flank drops to a value that is nearly nothing rather than to
    //     a value that is merely less.
    //
    // Glass is not a ring of even thickness. It is a bright catch along the top
    // and the corner arcs and almost nothing along the rest; what carries its
    // presence is the shadow around it, not a drawn perimeter. The shadow is
    // already there, so the edge does not have to prove the card exists.
    //
    // The two divide the perimeter between them rather than doubling up on it,
    // and that is a property of the shadow rather than a hope: it carries
    // `offset: (0, 1)`, so it is at its weakest directly above the card and at
    // its strongest below. Measured over this library's brightest wallpaper, the
    // backdrop falls 172 -> 158 above the card and 237 -> 146 below it, which is
    // the opposite ordering to the catch (0.44 at the top, 0.13 at the bottom).
    // The boundary is a bright line where the shade is thin and a pool of shade
    // where the line is not there.
    //
    // It costs nothing extra: a plain Rectangle declared inside `surround`,
    // whose layer is already masked to the complement of the card - so the mask
    // cuts it down to the band outside the card by itself, and the shading is
    // the Rectangle's own gradient. No second layer, no second mask, and
    // nothing re-rendering the backdrop, which is the cost this whole component
    // is arranged to avoid.
    readonly property real edgeSpecularWidth: Appearance.borderWidth.standard

    // Where the light rolls off the edge, as a fraction of the card's height:
    // the corner arc is the piece of the outline whose normal turns from facing
    // UP to facing SIDEWAYS, so it is exactly the run over which a lamp
    // overhead stops reaching the edge. Expressed against `cardRadius` rather
    // than as a number, so a change to the corner moves the roll-off with it
    // instead of leaving a rim that is bright right round the bend.
    readonly property real edgeRollOff: root.card.height > 0
        ? Math.min(0.5, root.cardRadius / root.card.height) : 0

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
        // where this is: a bright catch standing on the near edge of a pool of
        // shade is the whole of what reads as glass, and a shadow drawn over it
        // would be a shadow of the card cast onto the card's own rim.
        //
        // It is grown from the card and cut back to it by `surround`'s mask, so
        // its inner boundary IS the card's edge - to the same antialiased pixel
        // as the corner, because it is the same mask that makes the corner.
        Rectangle {
            id: edgeSpecular
            x: root.card.x - root.edgeSpecularWidth
            y: root.card.y - root.edgeSpecularWidth
            width: root.card.width + 2 * root.edgeSpecularWidth
            height: root.card.height + 2 * root.edgeSpecularWidth
            radius: root.cardRadius > 0 ? root.cardRadius + root.edgeSpecularWidth : 0
            antialiasing: true
            // The non-uniformity is not a flourish on top of a rim, it IS the
            // edge: everywhere the light does not catch, there is deliberately
            // almost nothing here, and the shadow outside is what says the card
            // is a separate object. A rim at one strength all the way round is a
            // stroke however bright it is, and a rim at two thirds of one
            // strength all the way round is the same stroke a shade fainter -
            // which is what shipped, and what still read as a border.
            //
            // The roll-off happens over the CORNER, not over the flank. Shipped
            // as a plain 0 / 0.5 / 1 ramp, the run from the top's value to the
            // side's value was half the card - so both top corners were as
            // bright as the top edge and the whole 3872px top read as one
            // uniform stroke (measured on the real desktop: crest 111/255 median
            // along the top against 37 along the left). Holding the top's value
            // only to the end of the arc and the flank's along the whole flank
            // is the same idea, applied on the geometry that actually turns.
            //
            // The bottom is a bounce off whatever the card is lying on, so it is
            // a hint above the flank rather than symmetric with the top.
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Appearance.colors.colGlassSpecular, 0.44) }
                GradientStop { position: root.edgeRollOff; color: Qt.alpha(Appearance.colors.colGlassSpecular, 0.07) }
                GradientStop { position: 1 - root.edgeRollOff; color: Qt.alpha(Appearance.colors.colGlassSpecular, 0.07) }
                GradientStop { position: 1; color: Qt.alpha(Appearance.colors.colGlassSpecular, 0.13) }
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

    // Nothing is drawn INSIDE the card, and that is the point rather than an
    // omission.
    //
    // Two things have sat here in turn. A 1px `colLayer0Border` outline, on the
    // reasoning that every floating surface in this shell carries one beside its
    // shadow - which measured as a notch, a dark line between the two bright
    // bands either side of it, and went in 1df616e62. Then a 1px
    // `colGlassSpecular` highlight at 0.16, on the reasoning that the specular
    // needs a near side or it is a line balanced on the seam.
    //
    // The second is the first wearing the other colour. It cannot ride
    // `surround`'s mask - it is inside the card, which is exactly what that mask
    // removes - so it is a uniform border rather than a shaded band, drawn at
    // one strength round all 9922px of a 3872x1089 perimeter, compositing over
    // the DESKTOP rather than over the backdrop. Measured on the real desktop it
    // was the brightest thing on the boundary on three edges out of four: +41
    // levels over a wallpaper at 105 on the left flank, +35 over one at 36 along
    // the top. A line that is brighter than the specular it is supposedly
    // supporting is the edge, and a line of even thickness all the way round is
    // a border.
    //
    // docs/M3_GUIDELINES.md §1 is what licenses the absence: "visible borders
    // are not required for every surface". The job the guideline gives an
    // outline - defining edges against complex backgrounds - belongs here to the
    // shadow and to the specular's catch, and both of those already vary round
    // the perimeter the way a real edge does.
}
