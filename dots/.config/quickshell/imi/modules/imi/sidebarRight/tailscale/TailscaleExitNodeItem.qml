import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root
    // Exit-node entry from Tailscale.exitNodes, or null for "None (direct)".
    property var exitNode: null
    readonly property bool isNone: root.exitNode === null

    // Whether this row is the current exit node, and what a pick does, are
    // the dialog's: it has the service. The row draws.
    signal picked(var exitNode)
    onClicked: root.picked(root.exitNode)

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
            text: root.active ? "radio_button_checked" : "radio_button_unchecked"
            color: root.active ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
                text: root.isNone ? Translation.tr("None (direct)") : root.exitNode.name
                textFormat: Text.PlainText
            }
            StyledText {
                Layout.fillWidth: true
                visible: !root.isNone && (root.exitNode.ip ?? "").length > 0
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideRight
                text: root.isNone ? "" : root.exitNode.ip
                textFormat: Text.PlainText
            }
        }

        MaterialSymbol {
            visible: !root.isNone && !root.exitNode.online
            text: "cloud_off"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant

            // A StyledToolTip follows its parent's `hovered`, and a symbol
            // has none - which reads as "always", so an offline node's
            // tooltip was pinned open. Gated on a hover area of its own.
            MouseArea {
                id: offlineHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
            StyledToolTip {
                extraVisibleCondition: false
                alternativeVisibleCondition: offlineHover.containsMouse
                text: Translation.tr("Offline")
            }
        }
    }
}
