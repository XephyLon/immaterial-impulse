import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "../../../services/modes/ModeSchema.js" as ModeSchema

/** HH:MM field on the shell's pill field; `committed` fires only with a valid time. */
ToolbarTextField {
    id: root

    property string value: "00:00"
    signal committed(string value)
    readonly property bool valid: ModeSchema.validTime(root.text)

    Layout.fillHeight: false
    implicitWidth: 72
    implicitHeight: 36
    horizontalAlignment: TextInput.AlignHCenter
    inputMask: "99:99"
    font.family: Appearance.font.family.numbers
    colBackground: Appearance.colors.colLayer3
    color: Appearance.colors.colOnLayer3
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
