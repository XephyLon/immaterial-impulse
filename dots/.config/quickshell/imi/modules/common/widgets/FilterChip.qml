import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A toggleable filter chip: optional leading icon plus a label. Used by both
 * plugin filter surfaces (the Widgets page and the plugin store) so the two
 * cannot drift apart - this was a page-local component in PluginStorePage,
 * which meant the only working implementation lived behind a feature gate.
 *
 * Selection state is the caller's: bind `toggled` and handle `clicked`.
 */
RippleButton {
    id: chip
    property string label
    property string chipIcon: ""
    implicitHeight: 32
    implicitWidth: chipRow.implicitWidth + Appearance.spacing.space200
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2
    colBackgroundToggled: Appearance.colors.colSecondaryContainer

    contentItem: RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: Appearance.spacing.space50

        MaterialSymbol {
            visible: chip.chipIcon.length > 0
            text: chip.chipIcon
            iconSize: Appearance.font.pixelSize.normal
            color: chip.toggled
                ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnLayer2
        }
        StyledText {
            text: chip.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: chip.toggled
                ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnLayer2
        }
    }
}
