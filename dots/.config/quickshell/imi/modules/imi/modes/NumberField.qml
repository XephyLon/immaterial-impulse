import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * An integer field on EditorField; empty means "not set" (null).
 * `from`/`to` bound it, `suffix` names the unit after the number ("%").
 */
EditorField {
    id: root

    property var value: null
    property int from: 0
    property int to: 100
    property string suffix: ""
    signal committed(var value)

    readonly property string valueText: root.value === null || root.value === undefined ? "" : String(root.value)

    implicitWidth: 72
    horizontalAlignment: root.suffix.length ? TextInput.AlignRight : TextInput.AlignHCenter
    rightPadding: root.suffix.length ? Appearance.spacing.space125 + suffixLabel.implicitWidth + Appearance.spacing.space25 : Appearance.spacing.space125
    font.family: Appearance.font.family.numbers
    validator: IntValidator {
        bottom: root.from
        top: root.to
    }

    // An emptied field is "intermediate" to the validator, which then holds
    // editingFinished back - so the commit also runs when focus leaves.
    function commit() {
        const next = root.text.trim().length ? Number(root.text) : null;
        if (next !== root.value)
            root.committed(next);
    }

    onValueTextChanged: if (!root.activeFocus) root.text = root.valueText
    Component.onCompleted: root.text = root.valueText
    onEditingFinished: root.commit()
    onActiveFocusChanged: if (!root.activeFocus) root.commit()

    StyledText {
        id: suffixLabel
        visible: root.suffix.length > 0
        anchors {
            right: parent.right
            rightMargin: Appearance.spacing.space125
            verticalCenter: parent.verticalCenter
        }
        text: root.suffix
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }
}
