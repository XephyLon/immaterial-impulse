import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "key_shapes.js" as KeyShapes
import QtQuick

RippleButton {
    id: root
    property var keyData
    property string key: keyData.label
    property string type: keyData.keytype
    property var keycode: keyData.keycode
    property string shape: keyData.shape
    property bool isShift: Ydotool.shiftKeys.includes(keycode)
    // The PHYSICAL key of the same code is down. Separate from the button's
    // own pressed state on purpose: this one is not a gesture on this widget,
    // it is a report about the hardware, and a key can be both (the user
    // taps the OSK's Shift while holding the real one).
    readonly property bool physicallyDown: KeyMonitor.isDown(root.keycode)
    property bool isBackspace: (key.toLowerCase() == "backspace")
    property bool isEnter: (key.toLowerCase() == "enter" || key.toLowerCase() == "return")
    // 44 rather than a round 45 so that the PITCH - a key plus the gap after
    // it - is a multiple of four, and a quarter-unit span is therefore a whole
    // number of pixels. QQuickLayout rounds every item's width UP, so a key
    // whose span lands on a half pixel is drawn half a pixel wide of where its
    // units put it, and fourteen spacers into the function row that is seven
    // pixels of drift against the row below.
    property real baseWidth: 44
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
    // A held physical key reads as the same surface a hovered one does, one
    // tier up - loud enough to find at a glance across a full-size keyboard,
    // and not so loud that a burst of typing strobes. The `empty` spacers are
    // excluded because they are not keys.
    colBackground: shape == "empty" ? ColorUtils.transparentize(Appearance.colors.colLayer1)
        : (root.physicallyDown ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1)
    Behavior on colBackground {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    buttonRadius: Appearance.rounding.small
    implicitWidth: root.baseWidth * root.widthUnits + root.keyGap * (root.widthUnits - 1)
    implicitHeight: root.baseHeight * root.heightUnits

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
        // A full-size keyboard puts four- and five-letter labels (Home, PgUp,
        // Super) on 1u and 1.25u caps, and a Text that does not fit paints
        // straight over its neighbours - there is no eliding that still reads
        // as a key. Shrink the label to the cap instead.
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: Appearance.font.pixelSize.smallest
        horizontalAlignment: Text.AlignHCenter
        color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
        text: root.isBackspace ? "backspace" : root.isEnter ? "subdirectory_arrow_left" :
            Ydotool.shiftMode == 2 ? (root.keyData.labelCaps || root.keyData.labelShift || root.keyData.label) :
            Ydotool.shiftMode == 1 ? (root.keyData.labelShift || root.keyData.label) : 
            root.keyData.label
    }
}
