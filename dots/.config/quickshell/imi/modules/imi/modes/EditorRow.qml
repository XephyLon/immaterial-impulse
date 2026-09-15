import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A plain settings row on the editor's card tier: the shell's CatalogueRow
 * (icon, label, hint) with whatever control is put inside it in the
 * affordance slot on the right. Rows that flip a switch are EditorSwitchRow.
 */
Rectangle {
    id: row
    property string icon
    property string label
    property string hint: ""
    default property alias control: catalogueRow.affordance

    Layout.fillWidth: true
    implicitHeight: Math.max(56, catalogueRow.implicitHeight + Appearance.spacing.space200)
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    CatalogueRow {
        id: catalogueRow
        anchors {
            fill: parent
            leftMargin: Appearance.spacing.space175
            rightMargin: Appearance.spacing.space175
        }
        rowIcon: row.icon
        rowIconSize: Appearance.font.pixelSize.huge
        title: row.label
        titleFillsWidth: true
        titleElides: true
        description: row.hint
    }
}
