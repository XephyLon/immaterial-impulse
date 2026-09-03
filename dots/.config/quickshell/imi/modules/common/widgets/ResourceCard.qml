import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    required property string label
    required property string iconText
    required property var iconShape
    required property real value
    required property string sublabel
    property color sublabelColor: Appearance.colors.colOnSurfaceVariant
    property int cardWidth: 150 
    // Which end of the bar is the trouble end. A usage card runs hot at the
    // top (a full disk is the problem); a LEVEL card - a battery, a health -
    // runs out at the bottom, and painting its full state in the error
    // colour alarms at exactly the state that is fine. `strain` is the
    // distance from the good end either way; the ramp and the warning
    // border read it, never `value`.
    property bool lowIsWarning: false
    // Where the warning starts, on strain - 0.9 is "over 90% used"; a
    // battery card passes 1 minus its low threshold.
    property real warnAt: 0.9
    readonly property real strain: root.lowIsWarning ? 1 - root.value : root.value
    readonly property bool warning: root.strain >= root.warnAt

    width: cardWidth
    height: 96 
    radius: Appearance.rounding.normal
    
    color: Appearance.colors.colSurfaceContainerLow

    function usageColor(v) {
        const s = root.lowIsWarning ? 1 - v : v
        if (s >= root.warnAt) return Appearance.colors.colError
        if (s > 0.6) return Appearance.colors.colTertiary || Appearance.m3colors.m3tertiary
        return Appearance.colors.colPrimary
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space150
        spacing: Appearance.spacing.space100

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: -Appearance.spacing.space50
            spacing: 0

            MaterialShapeWrappedMaterialSymbol {
                shape: root.iconShape
                text: root.iconText
                iconSize: Appearance.font.pixelSize.huge
                implicitSize: 28
                color: "transparent" // I know that you are going to give me color one day =P
                colSymbol: root.usageColor(root.value)
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: `${Math.round(root.value * 100)}%`
                font.pixelSize: Appearance.font.pixelSize.large || 18
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
                color: Appearance.colors.colOnSurface
                Layout.alignment: Qt.AlignVCenter
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space25

            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurface
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            StyledText {
                text: root.sublabel
                font.pixelSize: Appearance.font.pixelSize.smallest || 10
                color: root.sublabelColor
                font.features: { "tnum": 1 }
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        StyledProgressBar {
            Layout.fillWidth: true
            value: root.value
            highlightColor: root.usageColor(root.value)
            valueBarHeight: 6 

        }
    }

    border.width: root.warning ? Appearance.borderWidth.emphasis : 0
    border.color: root.warning ? Appearance.colors.colError : "transparent"
}
