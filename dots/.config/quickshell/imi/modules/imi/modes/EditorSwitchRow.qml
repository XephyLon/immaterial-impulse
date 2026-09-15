import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A settings switch row on the editor's card tier: the shell's ConfigSwitch
 * (icon, label, description, trailing switch, the whole row flips it) drawn
 * as one of the editor's rounded `colLayer2` cards.
 */
ConfigSwitch {
    id: row

    Layout.fillWidth: true
    implicitHeight: Math.max(56, contentItem.implicitHeight + Appearance.spacing.space200)
    leftPadding: Appearance.spacing.space175
    rightPadding: Appearance.spacing.space175
    buttonRadius: Appearance.rounding.normal
    iconSize: Appearance.font.pixelSize.huge
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
}
