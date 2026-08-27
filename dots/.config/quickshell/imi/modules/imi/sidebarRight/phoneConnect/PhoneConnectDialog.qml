import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 480

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space100

        WindowDialogTitle {
            Layout.fillWidth: true
            text: Translation.tr("Phone Connect")
        }

        DialogButton {
            id: refreshButton
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: implicitHeight

            onClicked: PhoneConnect.refresh()

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.centerIn: parent
                text: "refresh"
                iconSize: Appearance.font.pixelSize.larger
                color: refreshButton.colEnabled
            }

            StyledToolTip {
                text: Translation.tr("Refresh")
            }
        }
    }
    WindowDialogSeparator {}
    ListView {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -Appearance.spacing.space200
        Layout.bottomMargin: -Appearance.spacing.space200
        Layout.leftMargin: -root.contentPadding
        Layout.rightMargin: -root.contentPadding

        clip: true
        spacing: 0

        model: ScriptModel {
            values: PhoneConnect.devices
        }
        delegate: PhoneConnectDeviceItem {
            required property var modelData
            device: modelData
            width: ListView.view.width
        }
    }
    StyledText {
        visible: PhoneConnect.devices.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
        text: !PhoneConnect.installed
            ? Translation.tr("busctl was not found on PATH")
            : !PhoneConnect.available
                ? Translation.tr("Neither KDE Connect nor Valent is running")
                : Translation.tr("No devices yet — pair your phone from KDE Connect or Valent")
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        StyledText {
            visible: PhoneConnect.available
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: PhoneConnect.backend === "kdeconnect"
                ? Translation.tr("Backend: KDE Connect")
                : Translation.tr("Backend: Valent")
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
