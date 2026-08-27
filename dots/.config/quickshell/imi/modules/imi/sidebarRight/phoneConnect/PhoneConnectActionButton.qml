import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * One round action on the phone panel's action row. The row is the fork's
 * shape; each button here is an action the service answers, and the
 * control dims itself while it cannot (RippleButton owns the disabled dim,
 * so nothing in here repeats it).
 */
RippleButton {
    id: root
    property string glyph
    property string label

    implicitWidth: 48
    implicitHeight: 48
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colPrimaryContainer
    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
    colRipple: Appearance.colors.colPrimaryContainerActive

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.glyph
        iconSize: Appearance.font.pixelSize.huge
        color: Appearance.colors.colOnPrimaryContainer
    }

    StyledToolTip {
        text: root.label
    }
}
