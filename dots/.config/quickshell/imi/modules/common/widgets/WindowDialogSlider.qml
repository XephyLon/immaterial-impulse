pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

Column {
    id: root

    property alias text: sliderName.text
    property alias from: sliderWidget.from
    property alias to: sliderWidget.to
    property alias value: sliderWidget.value
    property alias tooltipContent: sliderWidget.tooltipContent
    property alias stopIndicatorValues: sliderWidget.stopIndicatorValues

    signal moved()
    
    spacing: -Appearance.spacing.space25
    ContentSubsectionLabel {
        id: sliderName
        visible: text?.length > 0
        text: ""
        anchors {
            left: parent.left
            right: parent.right
        }
    }
    StyledSlider {
        id: sliderWidget
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: Appearance.spacing.space50
            rightMargin: Appearance.spacing.space50
        }
        configuration: StyledSlider.Configuration.S
        onMoved: root.moved()
    }
}
