import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The part of the phone panel that owns whatever height the rows above and
 * below it leave. It will hold the phone's mirrored notifications
 * (docs/proposals/phone-connect.md, slice 1 of "Next slices"); until then it
 * is an empty state that says what it is for - and, while the panel has no
 * device to show, why.
 */
Item {
    id: root

    readonly property string headline: {
        if (!PhoneConnect.installed) return Translation.tr("busctl was not found");
        if (!PhoneConnect.available) return Translation.tr("No phone daemon is running");
        if (PhoneConnect.devices.length === 0) return Translation.tr("No devices yet");
        return Translation.tr("No notifications");
    }
    readonly property string detail: {
        if (!PhoneConnect.installed) return Translation.tr("Phone Connect drives KDE Connect and Valent over D-Bus through busctl, which ships with systemd.");
        if (!PhoneConnect.available) return Translation.tr("Start KDE Connect or Valent to see your phone here.");
        if (PhoneConnect.devices.length === 0) return Translation.tr("Pair your phone from KDE Connect or Valent and it will appear here.");
        return Translation.tr("Your phone's notifications are not mirrored yet.");
    }

    implicitHeight: emptyState.implicitHeight

    ColumnLayout {
        id: emptyState
        anchors.centerIn: parent
        width: parent.width
        spacing: Appearance.spacing.space100

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            iconSize: 40
            color: Appearance.colors.colSubtext
            text: PhoneConnect.devices.length === 0 ? "mobile_off" : "notifications_off"
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.normal
            text: root.headline
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: root.detail
        }
    }
}
