import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import qs.services

RowLayout {
    id: root
    spacing: Appearance.spacing.space150
    Layout.leftMargin: Appearance.spacing.space100
    Layout.rightMargin: Appearance.spacing.space100

    property string text: ""
    property string buttonIcon: ""
    property real value: 0
    property alias stopIndicatorValues: slider.stopIndicatorValues
    property bool usePercentTooltip: true
    property real from: 0
    property real to: 1
    // See ConfigSpinBox: only a drag is an edit. `value` also runs through
    // StyledSlider's `Behavior`, so binding a write to `onValueChanged` wrote
    // every intermediate animation frame to the config as well.
    signal valueModified(real newValue)
    property real textWidth: 120
    property bool showLabel: true

    RowLayout {
        id: row
        visible: root.showLabel
        spacing: Appearance.spacing.space150

        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
        }
        StyledText {
            id: labelWidget
            // Preferred, not minimum: the label may shrink and elide in a
            // narrow pane. Pinning a floor here would push the row wider than
            // its container for every ConfigSlider in the settings window.
            Layout.preferredWidth: root.textWidth
            Layout.maximumWidth: root.textWidth
            text: root.text
            elide: Text.ElideRight
            clip: true
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
    StyledSlider {
        id: slider
        Layout.fillWidth: true
        Layout.minimumWidth: 96
        configuration: StyledSlider.Configuration.XS
        usePercentTooltip: root.usePercentTooltip
        value: root.value
        from: Math.min(root.from, root.value)
        to: Math.max(root.to, root.value)
        // `value` lags behind the drag because of the Behavior above;
        // `valueAt(position)` is the value the handle is actually at.
        onMoved: root.valueModified(slider.valueAt(slider.position))
    }
}
