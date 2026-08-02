import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls

/**
 * Material 3 styled SpinBox component.
 */
SpinBox {
    id: root

    // Emitted for a change the user actually made, and never for one that
    // arrived from a binding. QQC2 raises `valueModified` itself for the
    // buttons, the wheel and the arrow keys, but it only wires the text field
    // up when `contentItem` *is* the TextInput - this one wraps it in an Item
    // to centre it, so the typed path has to report itself.
    signal userModified

    property real baseHeight: 35
    property real radius: Appearance.rounding.small
    property real innerButtonRadius: Appearance.rounding.unsharpen
    editable: true

    // The style computes these for a skin with both indicators on one side.
    // This one puts decrement at the left end and increment at the right, so
    // the defaults (4 / 39 here) lay the editable text field straight over the
    // decrement button, which then swallows its clicks: only the leftmost few
    // pixels of that button did anything at all.
    leftPadding: root.down.indicator ? root.down.indicator.width : 0
    rightPadding: root.up.indicator ? root.up.indicator.width : 0

    onValueModified: root.userModified()

    opacity: root.enabled ? 1 : 0.4

    background: Rectangle {
        color: Appearance.colors.colLayer2
        radius: root.radius
    }

    contentItem: Item {
        implicitHeight: root.baseHeight
        implicitWidth: Math.max(labelText.implicitWidth, 40)

        StyledTextInput {
            id: labelText
            anchors.centerIn: parent
            text: root.value // displayText would make the numbers weird like 1,000 instead of 1000
            color: Appearance.colors.colOnLayer2
            font.family: Appearance.font.family.numbers
            font.variableAxes: Appearance.font.variableAxes.numbers
            font.pixelSize: Appearance.font.pixelSize.small
            validator: root.validator
            // `onTextChanged` also fires when the binding above refreshes the
            // text, which made every construction of this control write its
            // own value straight back out. `onTextEdited` is the user-only
            // half of the same signal.
            onTextEdited: {
                const parsed = parseFloat(labelText.text);
                if (isNaN(parsed))
                    return;
                root.value = parsed;
                root.userModified();
            }
        }
    }

    down.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topLeftRadius: root.radius
        bottomLeftRadius: root.radius
        topRightRadius: root.innerButtonRadius
        bottomRightRadius: root.innerButtonRadius

        color: root.down.pressed ? Appearance.colors.colLayer2Active : 
            root.down.hovered ? Appearance.colors.colLayer2Hover : 
            ColorUtils.transparentize(Appearance.colors.colLayer2)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "remove"
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }

    up.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            right: parent.right
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topRightRadius: root.radius
        bottomRightRadius: root.radius
        topLeftRadius: root.innerButtonRadius
        bottomLeftRadius: root.innerButtonRadius

        color: root.up.pressed ? Appearance.colors.colLayer2Active : 
            root.up.hovered ? Appearance.colors.colLayer2Hover : 
            ColorUtils.transparentize(Appearance.colors.colLayer2)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }
}
