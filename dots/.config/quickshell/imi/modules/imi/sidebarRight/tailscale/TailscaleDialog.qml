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
            text: Translation.tr("Tailscale exit node")
        }

        DialogButton {
            id: refreshButton
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: implicitHeight

            onClicked: Tailscale.refresh()

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

        // First row clears the exit node; the rest are the advertised peers.
        header: TailscaleExitNodeItem {
            exitNode: null
            active: !Tailscale.exitNodeActive
            width: ListView.view.width
            onPicked: Tailscale.clearExitNode()
        }
        model: ScriptModel {
            values: Tailscale.exitNodes
        }
        delegate: TailscaleExitNodeItem {
            required property var modelData
            exitNode: modelData
            active: modelData.active === true
            width: ListView.view.width
            onPicked: node => Tailscale.setExitNode(node.ip)
        }
    }
    StyledText {
        visible: Tailscale.exitNodes.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
        text: !Tailscale.available
            ? Translation.tr("Tailscale daemon is not running")
            : !Tailscale.running
                ? Translation.tr("Tailscale is down")
                : Translation.tr("No peer advertises itself as an exit node")
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Tailscale.running ? Translation.tr("Turn off") : Translation.tr("Turn on")
            enabled: Tailscale.installed
            onClicked: Tailscale.toggle()
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
