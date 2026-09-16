import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The two cards that lead out of the tab: Contacts and Android Apps.
 *
 * Each says what it holds rather than only what it is - the contacts count
 * as the vCard monitor reports it, and whether this machine's scrcpy is new
 * enough for App Mode - because "Contacts >" tells the user nothing they
 * did not already know, and a card that opens onto an empty page is a
 * wasted trip. While the monitor has not answered, the subtitle says so
 * rather than claiming zero.
 *
 * The pages themselves are the other half of the Phone tab's split (see
 * Phone.qml's interface note); the card only names the id.
 */
Item {
    id: root

    property real appear: 1

    // The id Phone.qml resolves into an overlay page.
    signal openPage(string id)

    component NavCard: RippleButton {
        id: card
        property string glyph
        property string title
        property string subtitle
        property color colGlyphBackground: Appearance.colors.colPrimaryContainer
        property color colGlyph: Appearance.colors.colOnPrimaryContainer

        implicitHeight: 58
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active

        // The shell's catalogue row shape. The leading visual is a glyph on
        // a tonal disc rather than a bare symbol, so it goes through
        // `iconComponent`; the title's ink is stated because these cards sit
        // on layer 3.
        contentItem: CatalogueRow {
            anchors {
                fill: parent
                leftMargin: Appearance.spacing.space150
                rightMargin: Appearance.spacing.space100
            }
            rowSpacing: Appearance.spacing.space125

            iconComponent: Component {
                Rectangle {
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: Appearance.rounding.full
                    color: card.colGlyphBackground

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: card.glyph
                        iconSize: Appearance.font.pixelSize.larger
                        color: card.colGlyph
                    }
                }
            }

            title: card.title
            titleFont.pixelSize: Appearance.font.pixelSize.small
            titleColor: Appearance.colors.colOnLayer3
            titleFillsWidth: true
            titleElides: true
            description: card.subtitle
            descriptionWraps: false

            affordance: [
                MaterialSymbol {
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
            ]
        }
    }

    implicitHeight: cardRow.implicitHeight

    RowLayout {
        id: cardRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Appearance.spacing.space100

        NavCard {
            id: contactsCard
            Layout.fillWidth: true
            glyph: "contacts"
            colGlyphBackground: Appearance.colors.colPrimaryContainer
            colGlyph: Appearance.colors.colOnPrimaryContainer
            title: Translation.tr("Contacts")
            subtitle: {
                if (!PhoneContacts.ready) return Translation.tr("Syncing…");
                const count = PhoneContacts.count;
                return count === 1
                    ? Translation.tr("1 contact")
                    : Translation.tr("%1 contacts").arg(String(count));
            }
            onClicked: root.openPage("contacts")
        }

        NavCard {
            id: appsCard
            Layout.fillWidth: true
            glyph: "apps"
            colGlyphBackground: Appearance.colors.colSecondaryContainer
            colGlyph: Appearance.colors.colOnSecondaryContainer
            title: Translation.tr("Android Apps")
            subtitle: {
                if (!PhoneScrcpy.available) return Translation.tr("scrcpy is not installed");
                return PhoneScrcpy.appModeSupported
                    ? Translation.tr("scrcpy App Mode")
                    : Translation.tr("Requires scrcpy 4.0+");
            }
            onClicked: root.openPage("apps")
        }
    }
}
