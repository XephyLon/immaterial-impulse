import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Segmented choice for a form: `current` in, `picked(value)` out. Labelled,
 * it is the settings grammar's choice row (label left, chips right) at the
 * form's full width, flush with the form's other content; a caller that
 * puts it beside another control turns `Layout.fillWidth` off.
 */
ConfigSelectionArray {
    id: root
    property var current
    signal picked(var value)
    Layout.fillWidth: true
    Layout.leftMargin: 0
    Layout.rightMargin: 0
    currentValue: root.current
    onSelected: value => root.picked(value)
}
