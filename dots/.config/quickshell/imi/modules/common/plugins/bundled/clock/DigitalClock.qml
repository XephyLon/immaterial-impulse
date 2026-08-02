pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: clockColumn
    spacing: Appearance.spacing.space50

    property bool isVertical: false
    property bool showDate: true
    property bool animateTimeChange: true
    property color colText: Appearance.colors.colOnSecondaryContainer
    property var textHorizontalAlignment: Text.AlignHCenter

    property string clockFontFamily: Appearance.font.family.expressive
    property real clockFontSize: 90
    property real clockFontWeight: 350
    property real clockFontWidth: 100
    property real clockFontRoundness: 0

    property bool quoteShown: false
    property string quoteText: ""
    property string quoteFontFamily: Appearance.font.family.expressive

    // Time
    ClockText {
        id: timeTextTop
        text: clockColumn.isVertical ? DateTime.time.split(":")[0].padStart(2, "0") : DateTime.time
        color: clockColumn.colText
        horizontalAlignment: Text.AlignHCenter
        clockFontFamily: clockColumn.clockFontFamily
        animateChange: clockColumn.animateTimeChange
        font {
            pixelSize: clockColumn.clockFontSize
            weight: clockColumn.clockFontWeight
            variableAxes: ({
                "wdth": clockColumn.clockFontWidth,
                "ROND": clockColumn.clockFontRoundness
            })
        }
    }

    Loader {
        Layout.topMargin: -Appearance.spacing.space500
        Layout.fillWidth: true
        active: clockColumn.isVertical
        visible: active
        sourceComponent: ClockText {
            id: timeTextBottom
            text: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")
            color: clockColumn.colText
            horizontalAlignment: clockColumn.textHorizontalAlignment
            clockFontFamily: clockColumn.clockFontFamily
            animateChange: clockColumn.animateTimeChange
            font {
                pixelSize: timeTextTop.font.pixelSize
                weight: timeTextTop.font.weight
                variableAxes: timeTextTop.font.variableAxes
            }
        }
    }

    // Date
    ClockText {
        visible: clockColumn.showDate
        Layout.topMargin: -Appearance.spacing.space250
        Layout.fillWidth: true
        text: DateTime.longDate
        color: clockColumn.colText
        horizontalAlignment: clockColumn.textHorizontalAlignment
        clockFontFamily: clockColumn.clockFontFamily
        animateChange: clockColumn.animateTimeChange
    }

    // Quote
    ClockText {
        visible: clockColumn.quoteShown
        font.pixelSize: Appearance.font.pixelSize.normal
        text: clockColumn.quoteText
        // StyledText is a bare Text and so inherits Text.AutoText, which would
        // render anything markup-shaped the user typed into the quote field.
        textFormat: Text.PlainText
        animateChange: false
        color: clockColumn.colText
        horizontalAlignment: clockColumn.textHorizontalAlignment
        clockFontFamily: clockColumn.quoteFontFamily
    }
}
