import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * The dashed "Add …" row at the end of a section.
 */
RippleButton {
    id: addButton

    Layout.fillWidth: true
    implicitHeight: 42
    buttonRadius: Appearance.rounding.normal
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    // The outline traces the button's own rounded shape.
    DashedBorder {
        anchors.fill: parent
        radius: addButton.buttonRadius
        color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.4)
    }

    // A Control positions its content item itself; the row centres inside
    // a stretched Item rather than anchoring itself (which left it packed
    // to the leading edge).
    contentItem: Item {
        RowLayout {
            anchors.centerIn: parent
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                text: "add"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }

            StyledText {
                text: addButton.buttonText
                font.weight: Font.Medium
                color: Appearance.colors.colPrimary
            }
        }
    }
}
