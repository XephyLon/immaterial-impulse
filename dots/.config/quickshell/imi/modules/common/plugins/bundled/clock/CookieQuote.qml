import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects


Item {
    id: root

    property string quoteText: ""
    property string quoteFontFamily: Appearance.font.family.reading
    // The horizontal pixel clock leaves a band of empty space under its
    // glyphs, so the quote is lifted into it instead of sitting below.
    property bool aboveHorizontalPixelClock: false

    implicitWidth: quoteBox.implicitWidth
    implicitHeight: quoteBox.implicitHeight

    DropShadow {
        source: quoteBox
        anchors.fill: quoteBox
        horizontalOffset: 0
        verticalOffset: 2
        radius: Appearance.rounding.small
        samples: radius * 2 + 1
        color: Appearance.colors.colShadow
        transparentBorder: true
    }

    Rectangle {
        id: quoteBox
        y: root.aboveHorizontalPixelClock ? -26 : 0
        implicitWidth: quoteRow.implicitWidth + 8 * 2
        implicitHeight: quoteRow.implicitHeight + 4 * 2
        radius: Appearance.rounding.small
        color: Appearance.colors.colSecondaryContainer

        Row {
            id: quoteRow
            anchors.centerIn: parent
            spacing: Appearance.spacing.space50

            MaterialSymbol {
                id: quoteIcon
                anchors.top: parent.top
                iconSize: Appearance.font.pixelSize.huge
                text: "format_quote"
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                id: quoteStyledText
                horizontalAlignment: Text.AlignLeft
                text: root.quoteText
                // StyledText is a bare Text and so inherits Text.AutoText,
                // which would render anything markup-shaped the user typed
                // into the quote field.
                textFormat: Text.PlainText
                color: Appearance.colors.colOnSecondaryContainer
                font {
                    family: root.quoteFontFamily
                    pixelSize: Appearance.font.pixelSize.large
                    weight: Font.Normal
                }
            }
        }
    }
}
