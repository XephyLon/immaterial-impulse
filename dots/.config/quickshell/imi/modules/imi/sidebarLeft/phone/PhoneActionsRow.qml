import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.phone
import QtQuick
import QtQuick.Layouts

/**
 * ONE row of six round actions, in the fork's order: ring, ping, send the
 * clipboard, send a file, share the clipboard as a link or as text, browse
 * the phone's storage.
 *
 * Each button is enabled by two things and not one: the device has to be
 * reachable, and the BACKEND has to answer that action. Valent's action
 * names beyond findmyphone.ring were never verifiable against a live
 * daemon, so `canPing` / `canSendClipboard` / `canShare` / `canBrowseFiles`
 * are all kdeconnect-only and a Valent user gets a row where only Ring
 * lights up - which is honest, where a row of six live buttons that do
 * nothing is not. A seventh button belongs here only once the service
 * declares the call behind it; tests/test_phone_connect_contract.py fails
 * the suite on one that does not.
 */
Item {
    id: root

    // The device the tab is about; the row asks the service about it.
    property var device: null
    readonly property bool online: root.device !== null
        && root.device.paired && root.device.reachable

    property real appear: 1

    implicitHeight: actionRow.implicitHeight

    RowLayout {
        id: actionRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Appearance.spacing.space100

        PhoneActionButton {
            id: ringButton
            glyph: "phone_in_talk"
            label: Translation.tr("Ring phone")
            enabled: root.online
            onClicked: PhoneConnect.ring(root.device)
        }
        PhoneActionButton {
            id: pingButton
            glyph: "notifications_active"
            label: Translation.tr("Send a ping")
            enabled: root.online && PhoneConnect.canPing
            onClicked: PhoneConnect.ping(root.device)
        }
        PhoneActionButton {
            id: clipboardButton
            glyph: "content_paste"
            label: Translation.tr("Send clipboard to phone")
            enabled: root.online && PhoneConnect.canSendClipboard
            onClicked: PhoneConnect.sendClipboard(root.device)
        }
        PhoneActionButton {
            id: sendFileButton
            glyph: "file_upload"
            label: Translation.tr("Send file…")
            enabled: root.online && PhoneConnect.canShare
            onClicked: PhoneConnect.pickAndSendFiles(root.device)
        }
        PhoneActionButton {
            id: shareClipboardButton
            glyph: "link"
            label: Translation.tr("Share clipboard as a link or text")
            enabled: root.online && PhoneConnect.canShare
            onClicked: PhoneConnect.shareClipboard(root.device)
        }
        PhoneActionButton {
            id: browseFilesButton
            glyph: "folder_shared"
            label: Translation.tr("Browse phone files")
            enabled: root.online && PhoneConnect.canBrowseFiles
            onClicked: PhoneConnect.browseFiles(root.device)
        }
    }
}
