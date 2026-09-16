import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "../../../services/modes/ModeSchema.js" as ModeSchema

/** HH:MM field on EditorField; `committed` fires only with a valid time. */
EditorField {
    id: root

    property string value: "00:00"
    signal committed(string value)
    readonly property bool valid: ModeSchema.validTime(root.text)

    implicitWidth: 72
    horizontalAlignment: TextInput.AlignHCenter
    inputMask: "99:99"
    font.family: Appearance.font.family.numbers
    // The ring doubles as the validity mark: primary while editing, error
    // while the text is not a time.
    ringShown: root.activeFocus || !root.valid
    colRing: root.valid ? Appearance.colors.colPrimary : Appearance.colors.colError

    onValueChanged: if (!root.activeFocus) root.text = root.value
    Component.onCompleted: root.text = root.value
    onEditingFinished: {
        if (root.valid && root.text !== root.value)
            root.committed(root.text);
        else if (!root.valid)
            root.text = root.value;
    }
}
