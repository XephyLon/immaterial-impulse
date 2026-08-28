import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One row of a phone surface's roster: a device the daemon knows, its kind
 * and its state. Clicking it makes that device the one the chip, the pills
 * and the action row are about; the actions themselves live on the
 * surface's one action row, not here.
 */
DialogListItem {
    id: root
    // Device entry from PhoneConnect.devices. Optional rather than required:
    // a row built from a GroupedList's model is handed its entry by the plate
    // one frame after it loads, so every read below has to survive a null.
    property var device: null
    readonly property bool online: (root.device?.paired ?? false) && (root.device?.reachable ?? false)

    // M3 marks the chosen item of a menu with the selected container tone AND
    // a trailing check. `active` used only to cancel the hover colour, which
    // told the user which device was picked by drawing nothing at all.
    colBackground: root.active
        ? Appearance.colors.colSecondaryContainer
        : ColorUtils.transparentize(Appearance.colors.colLayer3)
    colBackgroundHover: root.active
        ? Appearance.colors.colSecondaryContainer
        : Appearance.colors.colLayer3Hover

    contentItem: RowLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: Appearance.spacing.space150

        MaterialSymbol {
            iconSize: Appearance.font.pixelSize.larger
            text: {
                switch (root.device?.type ?? "") {
                case "phone": return "smartphone";
                case "tablet": return "tablet";
                case "laptop": return "laptop";
                case "desktop": return "computer";
                case "tv": return "tv";
                default: return "devices";
                }
            }
            color: root.active ? Appearance.colors.colOnSecondaryContainer
                : root.online ? Appearance.colors.colPrimary
                : Appearance.colors.colOnSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                color: root.active ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
                text: root.device?.name || root.device?.id || ""
                textFormat: Text.PlainText
            }
            StyledText {
                Layout.fillWidth: true
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: {
                    if (!root.device) return "";
                    if (root.device.hasPairingRequest) return Translation.tr("Wants to pair");
                    if (!root.device.paired) return Translation.tr("Not paired");
                    if (!root.device.reachable) return Translation.tr("Paired • Offline");
                    if (root.device.batteryAvailable)
                        return root.device.batteryCharging
                            ? Translation.tr("%1% • Charging").arg(root.device.batteryCharge)
                            : Translation.tr("%1%").arg(root.device.batteryCharge);
                    return Translation.tr("Connected");
                }
            }
        }

        MaterialSymbol {
            objectName: "rosterSelectedCheck"
            visible: root.active
            text: "check"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
}
