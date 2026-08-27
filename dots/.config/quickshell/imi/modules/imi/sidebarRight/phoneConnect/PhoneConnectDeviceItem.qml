import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root
    // Device entry from PhoneConnect.devices.
    required property var device
    readonly property bool online: root.device.paired && root.device.reachable

    active: PhoneConnect.activeDevice !== null && PhoneConnect.activeDevice.id === root.device.id
    pointingHandCursor: false

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

        DialogButton {
            id: ringButton
            visible: root.online
            implicitWidth: implicitHeight

            onClicked: PhoneConnect.ring(root.device)

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "ring_volume"
                iconSize: Appearance.font.pixelSize.larger
                color: ringButton.colEnabled
            }

            StyledToolTip {
                text: Translation.tr("Ring")
            }
        }

        DialogButton {
            id: pingButton
            visible: root.online && PhoneConnect.canPing
            implicitWidth: implicitHeight

            onClicked: PhoneConnect.ping(root.device)

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "send"
                iconSize: Appearance.font.pixelSize.larger
                color: pingButton.colEnabled
            }

            StyledToolTip {
                text: Translation.tr("Ping")
            }
        }

        DialogButton {
            id: clipboardButton
            visible: root.online && PhoneConnect.canSendClipboard
            implicitWidth: implicitHeight

            onClicked: PhoneConnect.sendClipboard(root.device)

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "content_paste"
                iconSize: Appearance.font.pixelSize.larger
                color: clipboardButton.colEnabled
            }

            StyledToolTip {
                text: Translation.tr("Send clipboard")
            }
        }
    }
}
