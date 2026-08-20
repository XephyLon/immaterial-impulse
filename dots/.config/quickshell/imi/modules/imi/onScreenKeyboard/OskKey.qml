import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "key_shapes.js" as KeyShapes
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    property var keyData
    property string key: keyData.label
    property string type: keyData.keytype
    property var keycode: keyData.keycode
    property string shape: keyData.shape
    property bool isShift: Ydotool.shiftKeys.includes(keycode)
    property bool isBackspace: (key.toLowerCase() == "backspace")
    property bool isEnter: (key.toLowerCase() == "enter" || key.toLowerCase() == "return")
    property real baseWidth: 45
    property real baseHeight: 45
    // The gap a row leaves between two keys. A key spanning several units
    // covers the gaps it swallows as well as the key bodies, so this has to be
    // the same value OskContent gives its RowLayout or every wide key ends up
    // shorter than the keys it is supposed to span.
    readonly property real keyGap: Appearance.spacing.space100
    readonly property real widthUnits: KeyShapes.widthUnits[root.shape] ?? 1
    readonly property real heightUnits: KeyShapes.heightUnits[root.shape] ?? 1
    toggled: isShift ? Ydotool.shiftMode : false

    enabled: shape != "empty"
    colBackground: shape == "empty" ? ColorUtils.transparentize(Appearance.colors.colLayer1) : Appearance.colors.colLayer1
    buttonRadius: Appearance.rounding.small
    implicitWidth: root.baseWidth * root.widthUnits + root.keyGap * (root.widthUnits - 1)
    implicitHeight: root.baseHeight * root.heightUnits
    Layout.fillWidth: shape == "space" || shape == "expand"

    Connections {
        target: Ydotool
        enabled: isShift
        function onShiftModeChanged() {
            if (Ydotool.shiftMode == 0) {
                capsLockTimer.hasStarted = false;
            }
        }
    }

    Timer {
        id: capsLockTimer
        property bool hasStarted: false
        property bool canCaps: false
        interval: 300
        function startWaiting() {
            hasStarted = true;
            canCaps = true;
            start();
        }
        onTriggered: {
            canCaps = false;
        }
    }

    downAction: () => {
        Ydotool.press(root.keycode);
        if (isShift && Ydotool.shiftMode == 0) Ydotool.shiftMode = 1;
    }
    releaseAction: () => {
        if (root.type == "normal") {
            Ydotool.release(root.keycode);
            if (Ydotool.shiftMode == 1) {
                Ydotool.releaseShiftKeys()
            }
        } else if (isShift) {
            if (Ydotool.shiftMode == 1) {
                if (!capsLockTimer.hasStarted) {
                    capsLockTimer.startWaiting();
                } else {
                    if (capsLockTimer.canCaps) {
                        Ydotool.shiftMode = 2; // Caps lock mode
                    } else {
                        Ydotool.releaseShiftKeys()
                    }
                }
            } else if (Ydotool.shiftMode == 2) {
                Ydotool.releaseShiftKeys();
            }
        } else if (root.type == "modkey") {
            root.toggled = !root.toggled;
            if (!root.toggled) {
                if (isShift) {
                    Ydotool.releaseShiftKeys();
                } else { 
                    Ydotool.release(root.keycode);
                }
            }
        }

    }

    contentItem: StyledText {
        id: keyText
        anchors.fill: parent
        font.family: (isBackspace || isEnter) ? Appearance.font.family.iconMaterial : Appearance.font.family.main
        font.pixelSize: root.shape == "fn" ? Appearance.font.pixelSize.small : 
            (isBackspace || isEnter) ? Appearance.font.pixelSize.huge :
            Appearance.font.pixelSize.large
        horizontalAlignment: Text.AlignHCenter
        color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
        text: root.isBackspace ? "backspace" : root.isEnter ? "subdirectory_arrow_left" :
            Ydotool.shiftMode == 2 ? (root.keyData.labelCaps || root.keyData.labelShift || root.keyData.label) :
            Ydotool.shiftMode == 1 ? (root.keyData.labelShift || root.keyData.label) : 
            root.keyData.label
    }
}
