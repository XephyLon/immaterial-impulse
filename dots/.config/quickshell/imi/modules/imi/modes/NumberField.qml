import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * An integer field on the shell's pill field; empty means "not set" (null).
 * `from`/`to` bound it, `suffix` names the unit after the number ("%").
 */
ToolbarTextField {
    id: root

    property var value: null
    property int from: 0
    property int to: 100
    property string suffix: ""
    signal committed(var value)

    readonly property string valueText: root.value === null || root.value === undefined ? "" : String(root.value)

    Layout.fillHeight: false
    implicitWidth: 72
    implicitHeight: 36
    horizontalAlignment: root.suffix.length ? TextInput.AlignRight : TextInput.AlignHCenter
    rightPadding: root.suffix.length ? Appearance.spacing.space125 + suffixLabel.implicitWidth + Appearance.spacing.space25 : Appearance.spacing.space125
    font.family: Appearance.font.family.numbers
    focusRing: true
    colBackground: Appearance.colors.colLayer3
    color: Appearance.colors.colOnLayer3
    validator: IntValidator {
        bottom: root.from
        top: root.to
    }

    onValueTextChanged: if (!root.activeFocus) root.text = root.valueText
    Component.onCompleted: root.text = root.valueText
    onEditingFinished: {
        const next = root.text.trim().length ? Number(root.text) : null;
        if (next !== root.value)
            root.committed(next);
    }

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
