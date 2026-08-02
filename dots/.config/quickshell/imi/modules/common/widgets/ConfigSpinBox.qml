import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    property string text: ""
    property string icon
    // Shown as a hoverable "i" beside the control rather than inline, so a long
    // explanation doesn't stretch the row.
    property string infoText: ""
    property int value: 0
    property alias stepSize: spinBoxWidget.stepSize
    property int from: 0
    property int to: 99
    // Settings pages must write back from here, never from `onValueChanged`.
    // A value arriving from the config is not an edit, and treating it as one
    // is what let merely opening a page overwrite what the config already
    // held - see docs and tests/test_config_control_write_back.py.
    signal valueModified(int newValue)
    spacing: Appearance.spacing.space150
    Layout.leftMargin: Appearance.spacing.space100
    Layout.rightMargin: Appearance.spacing.space100

    RowLayout {
        spacing: Appearance.spacing.space150
        OptionalMaterialSymbol {
            icon: root.icon
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
            opacity: root.enabled ? 1 : 0.4
        }

        InfoTooltipIcon {
            tooltipText: root.infoText
            opacity: root.enabled ? 1 : 0.4
        }
    }

    StyledSpinBox {
        id: spinBoxWidget
        Layout.fillWidth: false
        // `from`/`to` bound what the user may dial in; they are not a
        // validator for what the config is allowed to already hold. Nothing in
        // Config.qml declares a range, so a hand-edited or preset-supplied
        // value outside this one is legitimate - widening to admit it shows the
        // truth and still only lets the user move back toward the range.
        from: Math.min(root.from, root.value)
        to: Math.max(root.to, root.value)
        value: root.value
        onUserModified: root.valueModified(spinBoxWidget.value)
    }
}
