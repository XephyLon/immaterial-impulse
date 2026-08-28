import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Material 3 button with expressive bounciness.
 * See https://m3.material.io/components/button-groups/overview
 *
 * Built ON RippleButton rather than beside it. Both were rooted on `Button`
 * and both spelled their own background, their own mouse handling and their
 * own press morph, which is why a button gained or lost its ripple according
 * to which of the two a call site happened to pick - the notification footer
 * lost its ripple the day it moved onto the group vocabulary. What is left
 * here is only what a button GROUP adds: the bounce, the segmented end radii
 * and the index bookkeeping that tells a button where in its group it sits.
 */
RippleButton {
    id: root
    property bool bounce: true
    property real baseWidth: contentItem.implicitWidth + horizontalPadding * 2
    property real baseHeight: contentItem.implicitHeight + verticalPadding * 2
    property bool enableImplicitWidthAnimation: true
    property bool enableImplicitHeightAnimation: true
    property real clickedWidth: baseWidth + (isAtSide ? 10 : 20)
    property real clickedHeight: baseHeight
    property var parentGroup: root.parent
    property int indexInParent: parentGroup?.children.indexOf(root) ?? -1
    property int clickIndex: parentGroup?.clickIndex ?? -1
    property bool isAtSide: indexInParent === 0 || indexInParent === (parentGroup?.childrenCount - 1)

    Layout.fillWidth: (clickIndex - 1 <= indexInParent && indexInParent <= clickIndex + 1)
    Layout.fillHeight: (clickIndex - 1 <= indexInParent && indexInParent <= clickIndex + 1)
    implicitWidth: (root.down && bounce) ? clickedWidth : baseWidth
    implicitHeight: (root.down && bounce) ? clickedHeight : baseHeight

    // The pressed state layer. M3 draws a press as the layer AND the ripple,
    // so these keep their own names and feed the ripple colours a call site
    // would otherwise have to set twice.
    property color colBackgroundActive: Appearance?.colors.colLayer1Active ?? "#D6CEE2"
    property color colBackgroundToggledActive: Appearance?.colors.colPrimaryActive ?? "#D6CEE2"
    colRipple: root.colBackgroundActive
    colRippleToggled: root.colBackgroundToggledActive

    // A group's ends are rounded and its joins are not, so the two sides are
    // named separately. They follow the shared press progress rather than
    // `down` directly: the corners ARRIVE at the pressed radius instead of
    // snapping there in one frame.
    property real radius: root.buttonEffectiveRadius
    property real leftRadius: root.buttonEffectiveRadius
    property real rightRadius: root.buttonEffectiveRadius
    cornerTopLeft: root.leftRadius
    cornerBottomLeft: root.leftRadius
    cornerTopRight: root.rightRadius
    cornerBottomRight: root.rightRadius

    property color color: root.enabled ? (root.toggled ?
        (root.down ? colBackgroundToggledActive :
            root.hovered ? colBackgroundToggledHover :
            colBackgroundToggled) :
        (root.down ? colBackgroundActive :
            root.hovered ? colBackgroundHover :
            colBackground)) : colBackground
    buttonColor: root.color

    // Keyboard focus is the one state with no pointer to show it.
    property bool tabbedTo: root.focus && (focusReason === Qt.TabFocusReason || focusReason === Qt.BacktabFocusReason)
    border: root.tabbedTo
    borderWidth: 2
    colBorder: Appearance.colors.colSecondary

    onDownChanged: {
        if (root.down) {
            if (root.parent.clickIndex !== undefined) {
                root.parent.clickIndex = parent.children.indexOf(root)
            }
        }
    }

    Behavior on implicitWidth {
        enabled: root.enableImplicitWidthAnimation
        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
    }

    Behavior on implicitHeight {
        enabled: root.enableImplicitHeightAnimation
        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
    }

    Behavior on leftRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on rightRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
}
