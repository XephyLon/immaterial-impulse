import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The frame every Phone sub-page is rooted on: a title bar with a back
 * affordance and whatever the page puts under it.
 *
 * The page does not own its own lifetime. `Phone.qml` hosts exactly one of
 * these at a time in an overlay Loader keyed on a string id, slides it in,
 * and pops it on `back()` or on Escape - so a page is a plain Item that
 * says what it is called and raises one signal, and nothing about the
 * overlay, the travel or the key handling is spelled a second time per
 * page.
 */
Item {
    id: root

    property string title: ""
    // Raised by the back affordance; Phone.qml pops the overlay. Escape is
    // the host's, not the page's - a page that handled it would have to be
    // focused, and the pages are not all focusable.
    signal back()

    default property alias content: contentHolder.data

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.space100

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            RippleButton {
                id: backButton
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.back()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: Translation.tr("Back")
                }
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer2
            }
        }

        // The content slot is a LAYOUT, because every page states its size
        // with Layout.* - its own header says so - and those attached
        // properties are inert in anything that is not one. As a plain Item
        // this slot left each page's root column at its IMPLICIT height:
        // measured on the Contacts page at 73px inside an 836px slot, so the
        // region under the search row was handed 0 and the list drew nothing
        // while reporting 2 rows and 110px of content.
        ColumnLayout {
            id: contentHolder
            Layout.fillWidth: true
            Layout.fillHeight: true
            // The page owns the rhythm between its own rows; this adds none.
            spacing: 0
        }
    }
}
