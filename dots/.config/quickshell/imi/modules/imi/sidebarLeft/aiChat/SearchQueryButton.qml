import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    property string query

    implicitHeight: 30
    leftPadding: Appearance.spacing.space100
    rightPadding: Appearance.spacing.space150
    buttonRadius: Appearance.rounding.verysmall
    colBackground: Appearance.colors.colSurfaceContainerHighest
    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
    colRipple: Appearance.colors.colSurfaceContainerHighestActive

    PointingHandInteraction {}
    // Which engine, which excluded sites, and whether the sidebar closes are
    // the chat's to know; the chip only says which query was asked for.
    signal searched(string query)
    onClicked: root.searched(root.query)

    contentItem: Item {
        anchors.centerIn: parent
        implicitWidth: rowLayout.implicitWidth
        implicitHeight: rowLayout.implicitHeight
        RowLayout {
            id: rowLayout
            anchors.centerIn: parent
            spacing: Appearance.spacing.space100
            MaterialSymbol {
                text: "search"
                iconSize: 20
                color: Appearance.m3colors.m3onSurface
            }
            StyledText {
                id: text
                horizontalAlignment: Text.AlignHCenter
                text: root.query
                color: Appearance.m3colors.m3onSurface
            }
        }
    }
}
