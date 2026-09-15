import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A single-line text field for a form: the shell's pill field on the card
 * tier. The value is committed on Enter or when focus leaves, never per
 * keystroke, so a half typed command is not saved (and applied) mid-way.
 * The text follows `value` from outside only while the field is not being
 * edited, so a commit the caller rewrites (or refuses) shows its result.
 */
ToolbarTextField {
    id: root

    property string value: ""
    property string placeholder: ""
    property bool monospace: false

    signal committed(string value)

    Layout.fillHeight: false
    implicitHeight: 36
    focusRing: true
    colBackground: Appearance.colors.colLayer3
    color: Appearance.colors.colOnLayer3
    placeholderText: root.placeholder
    font.family: root.monospace ? Appearance.font.family.monospace : Appearance.font.family.main

    onValueChanged: if (!root.activeFocus) root.text = root.value
    Component.onCompleted: root.text = root.value
    onEditingFinished: {
        if (root.text !== root.value)
            root.committed(root.text);
    }
}
