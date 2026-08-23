import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root

    property bool show: false
    default property alias data: contentColumn.data
    property real backgroundHeight: dialogBackground.implicitHeight
    property real backgroundWidth: 350
    property real backgroundAnimationMovementDistance: 60

    // The card holds its content in ONE padding, and the two things that have
    // to agree about it - the margin the content column takes, and the height
    // the card derives from the column - both come off this property.
    //
    // They used to be two separate spellings of `dialogBackground.radius`, so
    // the padding was 23px because the corner is 23px round rather than
    // because anyone chose 23 as a spacing value: restyling the corner
    // restyled the padding, and changing either spelling alone left the card a
    // different height from its content.
    property real contentPadding: Appearance.rounding.large
    
    signal dismiss()
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.dismiss();
            event.accepted = true;
        }
    }

    color: root.show ? Appearance.colors.colScrim : ColorUtils.transparentize(Appearance.colors.colScrim)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    visible: dialogBackground.implicitHeight > 0

    onShowChanged: {
        dialogBackgroundHeightAnimation.easing.bezierCurve = (show ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel)
        dialogBackground.implicitHeight = show ? backgroundHeight : 0
    }

    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    MouseArea { // Clicking outside the dialog should dismiss
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.dismiss()
    }

    // Every other floating body in this shell casts one - StyledPopup, the
    // toolbars, the tray menu, the notification cards - and the dialog card was
    // the one surface that sat on a scrim with nothing under it, so its edge
    // was a tonal step against the scrim and nothing else. Declared BEFORE the
    // card so it draws under it, and anchored to the card so it follows the
    // open animation's height rather than needing a gate of its own.
    StyledRectangularShadow {
        target: dialogBackground
    }

    Rectangle {
        id: dialogBackground
        anchors.horizontalCenter: parent.horizontalCenter
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh // Use opaque version of layer3
        
        property real targetY: root.height / 2 - root.backgroundHeight / 2
        y: root.show ? targetY : (targetY - root.backgroundAnimationMovementDistance)
        implicitWidth: root.backgroundWidth
        implicitHeight: contentColumn.implicitHeight + root.contentPadding * 2
        Behavior on implicitHeight {
            NumberAnimation {
                id: dialogBackgroundHeightAnimation
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: dialogBackgroundHeightAnimation.duration
                easing.type: dialogBackgroundHeightAnimation.easing.type
                easing.bezierCurve: dialogBackgroundHeightAnimation.easing.bezierCurve
            }
        }

        MouseArea { // So clicking inside the dialog won't dismiss
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
        }

        ColumnLayout {
            id: contentColumn
            // Published for the children that BLEED. A separator, a list or a
            // progress bar that runs to the card's edge cancels exactly this
            // padding, and every one of those call sites spelled it
            // `-Appearance.rounding.large` for the same reason the padding
            // itself did.
            readonly property real contentPadding: root.contentPadding
            anchors {
                fill: parent
                margins: root.contentPadding
            }
            spacing: Appearance.spacing.space200
            opacity: root.show ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

        }
    }
}
