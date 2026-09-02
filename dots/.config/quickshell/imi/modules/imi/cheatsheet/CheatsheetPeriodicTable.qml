import "periodic_table.js" as PTable
import "../../common/functions/cheatsheetFit.js" as CheatsheetFit
import QtQuick
import qs.modules.common

Item {
    id: root
    readonly property var elements: PTable.elements
    readonly property var series: PTable.series
    property real spacing: Appearance.spacing.space75
    // The room the page may take before the window it sizes runs past the
    // screen; 0 means "unknown", which leaves the table at its natural size.
    property real maxContentWidth: 0
    property real maxContentHeight: 0
    // The table is 18 columns of fixed tiles, ~1360x700 with its gaps - more
    // than a 1080p laptop at a fractional scale has, where it was the page
    // that put the whole cheatsheet under the bar and the dock. It shrinks as
    // one picture rather than re-flowing: the tiles keep their proportions
    // and the glyphs shrink with them.
    readonly property real fit: CheatsheetFit.fitScale(
        mainLayout.implicitWidth, mainLayout.implicitHeight,
        root.maxContentWidth, root.maxContentHeight)
    implicitWidth: mainLayout.implicitWidth * root.fit
    implicitHeight: mainLayout.implicitHeight * root.fit

    Column {
        id: mainLayout
        anchors.centerIn: parent
        spacing: root.spacing
        // Scaled about its own centre, which centerIn holds at the page's, so
        // the shrunk table lands exactly inside the box the page asks for.
        scale: root.fit

        Repeater { // Main table rows
            model: root.elements

            delegate: Row { // Table cells
                id: tableRow
                spacing: root.spacing
                required property var modelData

                Repeater {
                    model: tableRow.modelData
                    delegate: ElementTile {
                        required property var modelData
                        element: modelData
                    }

                }
            }

        }

        Item {
            id: gap
            implicitHeight: 20
        }

        Repeater { // Main table rows
            model: root.series

            delegate: Row { // Table cells
                id: seriesTableRow
                spacing: root.spacing
                required property var modelData

                Repeater {
                    model: seriesTableRow.modelData
                    delegate: ElementTile {
                        required property var modelData
                        element: modelData
                    }

                }
            }

        }
    }

}
