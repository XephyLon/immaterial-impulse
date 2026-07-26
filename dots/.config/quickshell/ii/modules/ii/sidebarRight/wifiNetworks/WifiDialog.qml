import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 600

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space100

        WindowDialogTitle {
            Layout.fillWidth: true
            text: Translation.tr("Connect to Wi-Fi")
        }

        DialogButton {
            id: rescanButton
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: implicitHeight

            enabled: !Network.wifiScanning
            opacity: enabled ? 1 : 0.4
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            onClicked: Network.rescanWifi()

            contentItem: MaterialSymbol {
                // Fill + center like DialogButton's own text contentItem;
                // anchors.centerIn inside the padded contentItem slot sat the
                // glyph off-center.
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "refresh"
                iconSize: Appearance.font.pixelSize.larger
                color: rescanButton.enabled ? rescanButton.colEnabled : rescanButton.colDisabled

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            StyledToolTip {
                text: Translation.tr("Rescan networks")
            }
        }
    }
    WindowDialogSeparator {
        visible: !Network.wifiScanning
    }
    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        Layout.fillWidth: true
        Layout.topMargin: -Appearance.spacing.space100
        Layout.bottomMargin: -Appearance.spacing.space100
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }
    ListView {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -Appearance.spacing.space200
        Layout.bottomMargin: -Appearance.spacing.space200
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large

        clip: true
        spacing: 0

        model: ScriptModel {
            values: Network.friendlyWifiNetworks
        }
        delegate: WifiNetworkItem {
            required property WifiAccessPoint modelData
            wifiNetwork: modelData
            width: ListView.view.width
        }
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
                GlobalStates.sidebarRightOpen = false;
            }
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