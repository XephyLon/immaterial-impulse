import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Focusable control that records one keyboard chord - modifiers plus a single
 * key - and renders it in the notation the keybind parser produces (mods as
 * SUPER/SHIFT/CTRL/ALT, keys as xkb-style names like Period or Page_Up).
 * Escape clears the pending capture instead of being captured, so it stays
 * usable as "back out" inside dialogs.
 */
Rectangle {
    id: root

    property var mods: []
    property string key: ""
    // Modifiers currently held while no final key has arrived yet.
    property var pendingMods: []
    readonly property bool hasChord: root.key.length > 0
    signal chordCaptured(var mods, string key)

    readonly property var keyNameMap: ({
        [Qt.Key_Space]: "Space",
        [Qt.Key_Return]: "Return",
        [Qt.Key_Enter]: "Return",
        [Qt.Key_Tab]: "Tab",
        [Qt.Key_Backtab]: "Tab",
        [Qt.Key_Backspace]: "BackSpace",
        [Qt.Key_Delete]: "Delete",
        [Qt.Key_Insert]: "Insert",
        [Qt.Key_Home]: "Home",
        [Qt.Key_End]: "End",
        [Qt.Key_PageUp]: "Page_Up",
        [Qt.Key_PageDown]: "Page_Down",
        [Qt.Key_Left]: "Left",
        [Qt.Key_Right]: "Right",
        [Qt.Key_Up]: "Up",
        [Qt.Key_Down]: "Down",
        [Qt.Key_Print]: "Print",
        [Qt.Key_Period]: "Period",
        [Qt.Key_Comma]: "Comma",
        [Qt.Key_Slash]: "Slash",
        [Qt.Key_Backslash]: "Backslash",
        [Qt.Key_Semicolon]: "Semicolon",
        [Qt.Key_Apostrophe]: "Apostrophe",
        [Qt.Key_Minus]: "Minus",
        [Qt.Key_Equal]: "Equal",
        [Qt.Key_BracketLeft]: "BracketLeft",
        [Qt.Key_BracketRight]: "BracketRight",
        [Qt.Key_QuoteLeft]: "Grave",
    })

    function modsFrom(eventModifiers) {
        const mods = [];
        if (eventModifiers & Qt.ControlModifier) mods.push("CTRL");
        if (eventModifiers & Qt.AltModifier) mods.push("ALT");
        if (eventModifiers & Qt.ShiftModifier) mods.push("SHIFT");
        if (eventModifiers & Qt.MetaModifier) mods.push("SUPER");
        return mods;
    }

    function keyNameFrom(event) {
        if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
            return String.fromCharCode("A".charCodeAt(0) + (event.key - Qt.Key_A));
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
            return String.fromCharCode("0".charCodeAt(0) + (event.key - Qt.Key_0));
        if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35)
            return "F" + (1 + event.key - Qt.Key_F1);
        return root.keyNameMap[event.key] ?? "";
    }

    function clear() {
        root.mods = [];
        root.key = "";
        root.pendingMods = [];
    }

    implicitHeight: 40
    implicitWidth: Math.max(160, contentRow.implicitWidth + Appearance.spacing.space300 * 2)
    radius: Appearance.rounding.small
    color: activeFocus ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
    border.width: Appearance.borderWidth.standard
    border.color: activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

    activeFocusOnTab: true

    Keys.onPressed: event => {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) {
            root.clear();
            return;
        }
        const isModifierKey = event.key === Qt.Key_Control || event.key === Qt.Key_Shift
            || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta
            || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R
            || event.key === Qt.Key_AltGr;
        if (isModifierKey) {
            root.pendingMods = root.modsFrom(event.modifiers);
            return;
        }
        const keyName = root.keyNameFrom(event);
        if (keyName.length === 0)
            return;
        root.mods = root.modsFrom(event.modifiers);
        root.key = keyName;
        root.pendingMods = [];
        root.chordCaptured(root.mods, root.key);
    }
    Keys.onReleased: event => {
        if (!root.hasChord)
            root.pendingMods = root.modsFrom(event.modifiers);
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.forceActiveFocus()
    }

    RowLayout {
        id: contentRow
        anchors.centerIn: parent
        spacing: Appearance.spacing.space50

        Repeater {
            model: root.hasChord ? [...root.mods, root.key] : root.pendingMods
            delegate: KeyboardKey {
                required property var modelData
                key: modelData
            }
        }

        StyledText {
            visible: !root.hasChord && root.pendingMods.length === 0
            text: root.activeFocus
                ? Translation.tr("Press the new shortcut...")
                : Translation.tr("Click, then press a shortcut")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
}
