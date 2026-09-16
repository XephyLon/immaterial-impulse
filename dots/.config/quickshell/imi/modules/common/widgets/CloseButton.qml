import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The close affordance of a whole surface (the Settings window, the
 * cheatsheet, the Modes manager): one 40px icon button, full radius, flat
 * on its surface with the layer's hover and ripple, the `close` glyph and
 * a "Close" tooltip. Placement (anchors, margins) is the caller's; the
 * shape is not. Three surfaces had each drawn their own - 32px with a
 * tooltip, 40px with a title-size glyph, the same plus a spin on hover.
 */
RippleButton {
    id: root
    property color colText: Appearance.colors.colOnLayer0

    implicitWidth: 40
    implicitHeight: 40
    buttonRadius: Appearance.rounding.full
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "close"
        iconSize: Appearance.font.pixelSize.larger
        color: root.colText
    }

    StyledToolTip {
        text: Translation.tr("Close")
    }
}
