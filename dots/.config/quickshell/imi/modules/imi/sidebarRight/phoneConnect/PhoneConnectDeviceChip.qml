import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The device the phone panel is about, as a chip: its kind as a glyph, its
 * name, and an arrow that opens the roster of every device the daemon
 * knows. With no device at all it still draws, so the panel has somewhere
 * to say so.
 */
RippleButton {
    id: root
    property var device: null
    property bool open: false

    implicitHeight: 36
    implicitWidth: chipRow.implicitWidth + Appearance.spacing.space300
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colRipple: Appearance.colors.colSecondaryContainerActive

    contentItem: RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: Appearance.spacing.space50

        MaterialSymbol {
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSecondaryContainer
            text: {
                switch (root.device?.type ?? "") {
                case "phone": return "smartphone";
                case "tablet": return "tablet";
                case "laptop": return "laptop";
                case "desktop": return "computer";
                case "tv": return "tv";
                case "": return "mobile_off";
                default: return "devices";
                }
            }
        }
        StyledText {
            Layout.maximumWidth: 180
            elide: Text.ElideRight
            // A device's name is the phone's own; never markup.
            textFormat: Text.PlainText
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSecondaryContainer
            text: root.device ? (root.device.name || root.device.id) : Translation.tr("No device")
        }
        MaterialSymbol {
            visible: root.enabled
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSecondaryContainer
            text: root.open ? "expand_less" : "expand_more"
        }
    }
}
