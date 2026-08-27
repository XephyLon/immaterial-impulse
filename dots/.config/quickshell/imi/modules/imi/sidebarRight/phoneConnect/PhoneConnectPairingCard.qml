import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A peer's pairing request, as a card in the phone panel's bottom stack,
 * with the two answers the daemon takes. The buttons sit in a
 * WindowDialogButtonRow so the filled-confirm / outlined-dismiss rule is
 * the row's to derive, not this card's to spell.
 */
Rectangle {
    id: root
    property var device: null

    implicitHeight: cardColumn.implicitHeight + Appearance.spacing.space200 * 2
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    ColumnLayout {
        id: cardColumn
        anchors {
            fill: parent
            margins: Appearance.spacing.space200
        }
        spacing: Appearance.spacing.space100

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space150

            MaterialSymbol {
                text: "handshake"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    // The peer's name is the peer's own; never markup.
                    textFormat: Text.PlainText
                    color: Appearance.colors.colOnLayer2
                    text: Translation.tr("%1 wants to pair").arg(root.device?.name || root.device?.id || "")
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: Translation.tr("Accept only if you started this from that device.")
                }
            }
        }

        WindowDialogButtonRow {
            Layout.fillWidth: true

            Item {
                Layout.fillWidth: true
            }
            DialogButton {
                id: declineButton
                buttonText: Translation.tr("Decline")
                onClicked: PhoneConnect.cancelPairing(root.device)
            }
            DialogButton {
                id: acceptButton
                buttonText: Translation.tr("Accept")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colEnabled: Appearance.colors.colOnPrimary
                onClicked: PhoneConnect.acceptPairing(root.device)
            }
        }
    }
}
