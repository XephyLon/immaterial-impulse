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
    // Everything the key knows about the KEYBOARD - which codes are shifts,
    // which physical key is down, which lock is latched, what shift mode the
    // typist is in - arrives from the board that built it. The key draws a
    // cap and reports gestures; it cannot press anything, and the board that
    // owns the input service answers the signals below.
    property bool isShift: false
    // 0 none, 1 shift held for one key, 2 caps: the board's state, mirrored.
    property int shiftMode: 0

    signal pressKey(var keycode)
    signal releaseKey(var keycode)
    signal shiftModeRequested(int mode)
    signal shiftKeysReleaseRequested()
    // The PHYSICAL key of the same code is down. Separate from the button's
    // own pressed state on purpose: this one is not a gesture on this widget,
    // it is a report about the hardware, and a key can be both (the user
    // taps the OSK's Shift while holding the real one).
    // Bound by the board to KeyMonitor's map - to the DATA, not to a call
    // over it: a binding captures the properties touched while it evaluates,
    // and routing it through `KeyMonitor.isDown()` once lost the dependency,
    // so the map updated and the key never redrew.
    property bool physicallyDown: false
    property bool isBackspace: (key.toLowerCase() == "backspace")
    property bool isEnter: (key.toLowerCase() == "enter" || key.toLowerCase() == "return")
    property real baseWidth: KeyShapes.baseKeyWidth
    property real baseHeight: KeyShapes.baseKeyHeight
    // The gap the grid leaves between two cells. A key spanning several units
    // covers the gaps it swallows as well as the key bodies, so this has to be
    // the same value OskContent gives its GridLayout or every wide key ends up
    // shorter than the keys it is supposed to span.
    readonly property real keyGap: Appearance.spacing.space100
    readonly property real widthUnits: KeyShapes.widthUnits[root.shape] ?? 1
    readonly property real heightUnits: KeyShapes.heightUnits[root.shape] ?? 1
    // Caps Lock and Num Lock are LATCHES, so what they show is the lock, not
    // the finger: a key that lit only while held would be the one pair on the
    // board whose lit state said the opposite of what the keyboard was doing
    // half the time. `KeyboardLocks` is the shell's existing answer for both
    // (it already drives the OSD), so this reads it rather than deriving a
    // second one from the LED events - which would be two sources that
    // disagree the moment one of them misses a toggle.
    //
    // Scroll Lock is deliberately not in here: `hyprctl devices` does not
    // report it, so it keeps the momentary treatment rather than being given
    // a lock state nothing can answer for.
    readonly property bool isCapsLock: root.keycode === 58
    readonly property bool isNumLock: root.keycode === 69
    // Bound by the board from KeyboardLocks, for the two keys above.
    property bool locked: false

    // A held physical key wears the toggled treatment rather than a surface a
    // tier up: `colLayer1` and `colLayer2` differ by a few levels on this
    // palette, which is legible on a panel and invisible on a key the size of
    // a fingertip. The toggled colour is the shell's own "this control is
    // active" language and needs no new token.
    toggled: root.locked || root.physicallyDown || (isShift && root.shiftMode !== 0)

    enabled: shape != "empty"
    colBackground: shape == "empty" ? ColorUtils.transparentize(Appearance.colors.colLayer1)
        : Appearance.colors.colLayer1
    buttonRadius: Appearance.rounding.small
    implicitWidth: root.baseWidth * root.widthUnits + root.keyGap * (root.widthUnits - 1)
    // A key TALLER than one unit spans whole rows and covers the gaps between
    // them, the same way a wide key covers the gaps along its row. A key
    // shorter than one unit - the function row's cap, a spacer - covers no gap
    // at all: it is drawn inside its own row rather than reaching into the
    // next, so the term is clamped instead of going negative.
    implicitHeight: root.baseHeight * root.heightUnits
        + root.keyGap * Math.max(0, root.heightUnits - 1)

    onShiftModeChanged: {
        if (isShift && root.shiftMode == 0)
            capsLockTimer.hasStarted = false;
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
        root.pressKey(root.keycode);
        if (isShift && root.shiftMode == 0) root.shiftModeRequested(1);
    }
    releaseAction: () => {
        if (root.type == "normal") {
            root.releaseKey(root.keycode);
            if (root.shiftMode == 1) {
                root.shiftKeysReleaseRequested()
            }
        } else if (isShift) {
            if (root.shiftMode == 1) {
                if (!capsLockTimer.hasStarted) {
                    capsLockTimer.startWaiting();
                } else {
                    if (capsLockTimer.canCaps) {
                        root.shiftModeRequested(2); // Caps lock mode
                    } else {
                        root.shiftKeysReleaseRequested()
                    }
                }
            } else if (root.shiftMode == 2) {
                root.shiftKeysReleaseRequested();
            }
        } else if (root.type == "modkey") {
            root.toggled = !root.toggled;
            if (!root.toggled) {
                if (isShift) {
                    root.shiftKeysReleaseRequested();
                } else { 
                    root.releaseKey(root.keycode);
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
            root.shiftMode == 2 ? (root.keyData.labelCaps || root.keyData.labelShift || root.keyData.label) :
            root.shiftMode == 1 ? (root.keyData.labelShift || root.keyData.label) : 
            root.keyData.label
    }
}
