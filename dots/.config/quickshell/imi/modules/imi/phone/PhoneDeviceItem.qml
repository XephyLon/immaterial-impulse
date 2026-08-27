import qs.services
import qs.modules.common
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
    // Device entry from PhoneConnect.devices.
    required property var device
    readonly property bool online: root.device.paired && root.device.reachable

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
                switch (root.device.type) {
                case "phone": return "smartphone";
                case "tablet": return "tablet";
                case "laptop": return "laptop";
                case "desktop": return "computer";
                case "tv": return "tv";
                default: return "devices";
                }
            }
            color: root.online ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
                text: root.device.name || root.device.id
                textFormat: Text.PlainText
            }
            StyledText {
                Layout.fillWidth: true
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: {
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
    }
}
