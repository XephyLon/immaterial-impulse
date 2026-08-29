import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls

/**
 * A button with ripple effect similar to in Material Design.
 */
Button {
    id: root
    property bool toggled
    property string buttonText
    property bool pointingHandCursor: true
    property real buttonRadius: Appearance?.rounding?.small ?? 4
    // The pressed radius is the shared model's tightening, unless a caller
    // names its own - a header button that squares off while open still wins.
    property real buttonRadiusPressed: buttonRadius * (Appearance?.interaction?.pressRadiusScale ?? 1)
    // ...and it ARRIVES there: the model's press progress is animated, so a
    // press no longer snaps the corners in one frame.
    property real buttonEffectiveRadius: root.buttonRadius
        + (root.buttonRadiusPressed - root.buttonRadius) * interactionMotion.pressProgress
    // Per-corner overrides, defaulting to the uniform radius. A button used as
    // the header of an expanding surface needs square bottom corners while
    // open so its hover and ripple blend into the content below instead of
    // leaving rounded notches.
    property real cornerTopLeft: root.buttonEffectiveRadius
    property real cornerTopRight: root.buttonEffectiveRadius
    property real cornerBottomLeft: root.buttonEffectiveRadius
    property real cornerBottomRight: root.buttonEffectiveRadius
    property int rippleDuration: 1200
    property bool rippleEnabled: true
    property var downAction // When left clicking (down)
    property var releaseAction // When left clicking (release)
    property var altAction // When right clicking
    property var middleClickAction // When middle clicking
    property bool border: false
    property real borderWidth: Appearance.borderWidth.standard
    property color colBorder: Appearance?.colors.colOutlineVariant ?? "#79747E"

    property color colBackground: ColorUtils.transparentize(Appearance?.colors.colLayer1Hover, 1) || "transparent"
    property color colBackgroundHover: Appearance?.colors.colLayer1Hover ?? "#E5DFED"
    property color colBackgroundToggled: Appearance?.colors.colPrimary ?? "#65558F"
    property color colBackgroundToggledHover: Appearance?.colors.colPrimaryHover ?? "#77699C"
    property color colRipple: Appearance?.colors.colLayer1Active ?? "#D6CEE2"
    property color colRippleToggled: Appearance?.colors.colPrimaryActive ?? "#D6CEE2"

    // Reveal factor for staggered entrances (see ExpandablePanel). Animating
    // this instead of `opacity` directly keeps the disabled-state binding
    // below alive - an imperative write to `opacity` destroys it, and every
    // disabled button then renders as if it were enabled.
    // The shared interaction states: hover lifts, press settles, disabled is
    // opacity only. The button keeps owning its colours and its ripple - this
    // drives the motion, and only the motion.
    property bool interactionMotionEnabled: true
    property InteractionMotion interactionMotion: InteractionMotion {
        hovered: root.hovered && root.interactionMotionEnabled
        down: root.down && root.interactionMotionEnabled
        controlEnabled: root.enabled
    }

    property real appear: 1
    opacity: root.interactionMotion.dimOpacity * root.appear
    // Staggered entrances read as motion, not just a fade: the button rises
    // into place as it appears. A Translate leaves `y` alone, which a layout
    // owns, so this is safe inside a Row/Flow/Layout.
    property real appearRise: 6
    // Two transforms, not one: the rise belongs to the entrance and the scale
    // to the interaction, and a control can be doing both at once.
    transform: [
        Translate { y: (1 - root.appear) * root.appearRise },
        Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            xScale: root.interactionMotion.scale
            yScale: root.interactionMotion.scale
        }
    ]
    property color buttonColor: ColorUtils.transparentize(root.toggled ? 
        (root.hovered ? colBackgroundToggledHover : 
            colBackgroundToggled) :
        (root.hovered ? colBackgroundHover : 
            colBackground), root.enabled ? 0 : 1)
    property color rippleColor: root.toggled ? colRippleToggled : colRipple

    function startRipple(x, y) {
        const stateY = buttonBackground.y;
        rippleAnim.x = x;
        rippleAnim.y = y - stateY;

        const dist = (ox,oy) => ox*ox + oy*oy
        const stateEndY = stateY + buttonBackground.height
        rippleAnim.radius = Math.sqrt(Math.max(dist(0, stateY), dist(0, stateEndY), dist(width, stateY), dist(width, stateEndY)))

        rippleFadeAnim.complete();
        rippleAnim.restart();
    }

    // The other half of `startRipple`, made reachable for the same reason it
    // is: a surface that drives this button's visuals without letting its
    // click through - the Components workbench - can start a ripple and had no
    // way to end one, so every previewed press left its ripple standing.
    function fadeRipple() {
        if (!root.rippleEnabled) return;
        rippleFadeAnim.restart();
    }

    component RippleAnim: NumberAnimation {
        duration: rippleDuration
        easing.type: Appearance?.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance?.animationCurves.standardDecel
    }

    // The pointer shape, stated as a handler rather than left to the MouseArea.
    //
    // A handler attaches to the item it is declared in - handlers are not
    // Items, so a Control's contentData rules never touch them - which makes
    // this the one way to say "this whole button is clickable" that cannot be
    // narrowed by a subclass replacing the contentItem.
    HoverHandler {
        cursorShape: root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    MouseArea {
        // Parented to the button ITSELF, not left to default parenting.
        //
        // This is declared in the body of a Control, so Qt treats it as
        // contentData and parents it into `contentItem`. With the default
        // contentItem - a StyledText the Control sizes to its padded rect -
        // that is almost the whole button and nobody noticed. Replace the
        // contentItem with something that sizes itself, and the area collapses
        // onto it: `IconToolbarButton` centres a 22px glyph, so every toolbar
        // button in the shell was hoverable and clickable on the icon alone
        // and dead across the rest of its 40px target. The pointer never
        // changed, which is how it was found.
        parent: root
        anchors.fill: root
        cursorShape: root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: (event) => { 
            if(event.button === Qt.RightButton) {
                if (root.altAction) root.altAction(event);
                return;
            }
            if(event.button === Qt.MiddleButton) {
                if (root.middleClickAction) root.middleClickAction();
                return;
            }
            root.down = true
            if (root.downAction) root.downAction();
            if (!root.rippleEnabled) return;
            const {x,y} = event
            root.startRipple(x, y)
        }
        onReleased: (event) => {
            root.down = false
            if (event.button != Qt.LeftButton) return;
            if (root.releaseAction) root.releaseAction();
            root.click() // Because the MouseArea already consumed the event
            if (!root.rippleEnabled) return;
            rippleFadeAnim.restart();
        }
        onCanceled: (event) => {
            root.down = false
            if (!root.rippleEnabled) return;
            rippleFadeAnim.restart();
        }
        // The touch spelling of the right-click action. A pointer has a
        // second button; a finger has a long press, and every button built
        // on this one should answer both the same way.
        onPressAndHold: () => {
            if (!root.altAction) return;
            root.altAction();
            root.down = false;
            if (root.rippleEnabled) rippleFadeAnim.restart();
        }
    }

    RippleAnim {
        id: rippleFadeAnim
        duration: rippleDuration * 2
        target: ripple
        property: "opacity"
        to: 0
    }

    SequentialAnimation {
        id: rippleAnim

        property real x
        property real y
        property real radius

        PropertyAction {
            target: ripple
            property: "x"
            value: rippleAnim.x
        }
        PropertyAction {
            target: ripple
            property: "y"
            value: rippleAnim.y
        }
        PropertyAction {
            target: ripple
            property: "opacity"
            value: 1
        }
        ParallelAnimation {
            RippleAnim {
                target: ripple
                properties: "implicitWidth,implicitHeight"
                from: 0
                to: rippleAnim.radius * 2
            }
        }
    }

    Component.onDestruction: {
        rippleAnim.stop();
        rippleFadeAnim.stop();
    }

    background: Rectangle {
        id: buttonBackground
        topLeftRadius: root.cornerTopLeft
        topRightRadius: root.cornerTopRight
        bottomLeftRadius: root.cornerBottomLeft
        bottomRightRadius: root.cornerBottomRight
        implicitHeight: 30

        color: root.buttonColor
        border.width: root.border ? root.borderWidth : 0
        border.color: root.colBorder
        Behavior on color {
            animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: buttonBackground.width
                height: buttonBackground.height
                topLeftRadius: root.cornerTopLeft
                topRightRadius: root.cornerTopRight
                bottomLeftRadius: root.cornerBottomLeft
                bottomRightRadius: root.cornerBottomRight
            }
        }

        Item {
            id: ripple
            width: ripple.implicitWidth
            height: ripple.implicitHeight
            opacity: 0
            visible: width > 0 && height > 0

            property real implicitWidth: 0
            property real implicitHeight: 0

            Behavior on opacity {
                animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RadialGradient {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.rippleColor }
                    GradientStop { position: 0.3; color: root.rippleColor }
                    GradientStop { position: 0.5; color: Qt.rgba(root.rippleColor.r, root.rippleColor.g, root.rippleColor.b, 0) }
                }
            }

            transform: Translate {
                x: -ripple.width / 2
                y: -ripple.height / 2
            }
        }
    }

    contentItem: StyledText {
        text: root.buttonText
    }
}
