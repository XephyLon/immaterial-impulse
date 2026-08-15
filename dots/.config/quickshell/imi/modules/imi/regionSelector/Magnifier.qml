import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "../../common/plugins/designsystem/widgets" as Expressive
import QtQuick
import Qt5Compat.GraphicalEffects

/**
 * A loupe at the cursor while a region is being framed.
 *
 * It samples the SAME frozen frame the selector already grabbed at open
 * (`screenshotSource`, a grim capture) rather than a live screencopy. Two
 * reasons, and the second is the one that matters: the selector's own comment
 * records that ScreencopyView's frozen frame can come from an older
 * compositor buffer, so a magnifier fed from it could disagree with the pixels
 * the crop will actually take - a loupe that lies about the edge you are
 * lining up is worse than none. And a live capture of a screen the overlay is
 * drawn on would show the overlay, then the loupe, then the loupe inside the
 * loupe.
 *
 * `smooth: false` is deliberate: this exists to show WHICH pixel, so it scales
 * nearest-neighbour. Interpolating would defeat the purpose at the exact
 * moment it is wanted, on a one-pixel edge.
 */
Item {
    id: root

    required property url source
    // Cursor position in the overlay's coordinates, which are the screen's.
    required property real pointerX
    required property real pointerY
    // The frame being sampled, so the loupe can offset within it.
    required property real frameWidth
    required property real frameHeight

    // What the click would do, said as a SHAPE. The glass is a MaterialShape
    // and ShapeCanvas morphs on any polygon change, so a state change animates
    // itself - the same mechanism the wallpaper picker and the widget cards
    // use. Circle at rest, a cookie while a region is being dragged out, and
    // the ghost when the pointer has locked onto a window.
    property bool framing: false
    property bool onWindow: false
    readonly property int glassShape: root.onWindow
        ? Expressive.MaterialShape.Shape.Ghostish
        : (root.framing ? Expressive.MaterialShape.Shape.Cookie6Sided
                        : Expressive.MaterialShape.Shape.Circle)

    property real zoom: 6
    property real loupeSize: 132 * Appearance.effectiveScale
    // How far the loupe sits from the cursor, so it never covers the pixel it
    // is describing.
    property real gap: 22 * Appearance.effectiveScale

    // Entering and leaving, on the shell's expressive tiers: the spatial curve
    // carries the scale (it overshoots slightly, so the marker arrives rather
    // than appears) and the effects curve carries the fade, which is the same
    // pairing the widget trees use for travel and fade. Scaled from the
    // cursor's own corner, so it grows out of the pointer instead of the
    // middle of the screen.
    property bool shown: true
    opacity: root.shown ? 1 : 0
    scale: root.shown ? 1 : 0.7
    visible: opacity > 0.01
    transformOrigin: root.flipX
        ? (root.flipY ? Item.TopLeft : Item.BottomLeft)
        : (root.flipY ? Item.TopRight : Item.BottomRight)
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    implicitWidth: loupeSize
    implicitHeight: loupeSize + readout.height + 4 * Appearance.effectiveScale

    // Up and to the LEFT by default, which is the opposite corner from the
    // action chip CursorGuide already puts at the cursor's bottom-right -
    // placed on the same side, the loupe sits on top of it.
    //
    // Each axis flips independently when that side would run off the screen,
    // because the edges are exactly where people frame most often and a loupe
    // cut in half there is a loupe missing when it is wanted most.
    readonly property bool flipX: root.pointerX - root.gap - width < 0
    readonly property bool flipY: root.pointerY - root.gap - height < 0
    x: root.flipX ? root.pointerX + root.gap : root.pointerX - root.gap - width
    y: root.flipY ? root.pointerY + root.gap : root.pointerY - root.gap - height

    Item {
        id: glass
        width: root.loupeSize
        height: root.loupeSize

        // The magnified frame, cut to the shape. A MultiEffect mask rather
        // than `clip: true`, because a rectangle clip cannot follow a polygon
        // - and this is the shell's own mask idiom (MaskMultiEffect).
        Item {
            id: glassContent
            anchors.fill: parent
            // Not drawn directly - OpacityMask below draws it through the
            // shape. Left unhidden so its layer keeps updating as the pointer
            // moves; `visible: false` stops the layer refreshing and the glass
            // shows the desktop straight through.
            layer.enabled: true
            visible: false

            Image {
                // The frame at `zoom`, shifted so the cursor's pixel lands in
                // the middle of the glass. Qt scales the loaded image on the
                // fly rather than allocating a texture of the scaled size, so
                // this costs the frame once however far it is zoomed - the
                // sourceClipRect version this replaced reloaded the file on
                // every pointer move and rendered nothing at all.
                source: root.source
                cache: false
                asynchronous: false
                smooth: false
                mipmap: false
                fillMode: Image.PreserveAspectFit
                width: root.frameWidth * root.zoom
                height: root.frameHeight * root.zoom
                x: -(root.pointerX * root.zoom) + glass.width / 2
                y: -(root.pointerY * root.zoom) + glass.height / 2
            }
        }

        Expressive.MaterialShape {
            id: glassMask
            anchors.fill: parent
            visible: false
            shape: root.glassShape
            color: "white"
        }

        OpacityMask {
            anchors.fill: parent
            source: glassContent
            maskSource: glassMask
            cached: false
        }

        // The outline, the same shape again so it tracks the morph.
        Expressive.MaterialShape {
            anchors.fill: parent
            shape: root.glassShape
            color: "transparent"
            borderWidth: 1
            borderColor: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.35)
        }

        // The crosshair marks the pixel the coordinates below name. Drawn as
        // two gaps rather than a solid cross so the pixel itself stays visible
        // - a crosshair that covers its own target is a common loupe bug.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: glass.height * 0.18
            width: 1
            height: glass.height / 2 - root.zoom - glass.height * 0.18
            color: Appearance.colors.colPrimary
            opacity: 0.9
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: glass.height / 2 + root.zoom
            width: 1
            height: glass.height / 2 - root.zoom - glass.height * 0.18
            color: Appearance.colors.colPrimary
            opacity: 0.9
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: glass.width * 0.18
            width: glass.width / 2 - root.zoom - glass.width * 0.18
            height: 1
            color: Appearance.colors.colPrimary
            opacity: 0.9
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: glass.width / 2 + root.zoom
            width: glass.width / 2 - root.zoom - glass.width * 0.18
            height: 1
            color: Appearance.colors.colPrimary
            opacity: 0.9
        }
        // The pixel under the crosshair, outlined at its magnified size.
        Rectangle {
            anchors.centerIn: parent
            width: root.zoom
            height: root.zoom
            color: "transparent"
            border.width: 1
            border.color: Appearance.colors.colPrimary
        }
    }

    Rectangle {
        id: readout
        anchors.top: glass.bottom
        anchors.topMargin: 4 * Appearance.effectiveScale
        anchors.horizontalCenter: glass.horizontalCenter
        width: coordinates.implicitWidth + 12 * Appearance.effectiveScale
        height: coordinates.implicitHeight + 4 * Appearance.effectiveScale
        radius: Appearance.rounding.verysmall
        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.15)

        StyledText {
            id: coordinates
            anchors.centerIn: parent
            // Whole pixels: a fractional coordinate is not a thing the crop
            // can act on, and the crop rounds anyway.
            text: `${Math.round(root.pointerX)}, ${Math.round(root.pointerY)}`
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colOnLayer0
        }
    }
}
