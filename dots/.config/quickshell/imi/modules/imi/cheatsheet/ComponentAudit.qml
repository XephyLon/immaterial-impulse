import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Every widget's measurements in one column, so an inconsistency is a number
 * out of line rather than a feeling.
 *
 * The gallery answers "what do we have"; this answers "do they agree". Sorting
 * by height puts a 36 next to a 32 that should have matched it; sorting by
 * radius separates the `rounding.full` chips from the `rounding.small` ones
 * and shows which family each control actually joined. The first pass over
 * this table found a device chip at 36/full beside the shared filter chip at
 * 32/small - two chips, two shapes, one of them written by hand.
 *
 * Everything is read off a BUILT widget. A table of what the files declare
 * would be a table of tokens, and half of these compute their height from a
 * font or their radius from their own height.
 */
Item {
    id: root

    required property var entries
    signal picked(var entry)

    property string sortKey: "type"
    property bool descending: false

    readonly property var columns: [
        { key: "type", name: Translation.tr("Component"), width: 260 },
        { key: "height", name: Translation.tr("Height"), width: 90 },
        { key: "width", name: Translation.tr("Width"), width: 90 },
        { key: "radius", name: Translation.tr("Radius"), width: 90 },
        { key: "horizontalPadding", name: Translation.tr("Pad h"), width: 90 },
        { key: "verticalPadding", name: Translation.tr("Pad v"), width: 90 },
        { key: "fontSize", name: Translation.tr("Font"), width: 80 },
    ]

    // Each row builds its widget once, off screen, and reports what it got.
    // Held here rather than in the delegate so sorting does not rebuild fifty
    // widgets on every click.
    property var measured: ({})

    function record(type, measurements) {
        const next = Object.assign({}, root.measured);
        next[type] = measurements;
        root.measured = next;
    }

    readonly property var rows: {
        const rows = root.entries.map(entry => {
            const type = (entry.type ?? "").split("/").pop().replace(".qml", "");
            const measurements = root.measured[entry.type] ?? null;
            return {
                entry: entry,
                type: type,
                height: measurements?.height,
                width: measurements?.width,
                radius: measurements?.radius,
                horizontalPadding: measurements?.horizontalPadding,
                verticalPadding: measurements?.verticalPadding,
                fontSize: measurements?.fontSize,
                built: measurements !== null,
            };
        });
        const key = root.sortKey;
        // A widget that could not be built has no numbers, and sorting it as
        // zero puts a whole block of "we do not know" at one end pretending to
        // be the smallest. Unbuilt rows sort last either way.
        rows.sort((left, right) => {
            const a = left[key];
            const b = right[key];
            if (a === undefined && b === undefined) return 0;
            if (a === undefined) return 1;
            if (b === undefined) return -1;
            const order = typeof a === "string" ? a.localeCompare(b) : a - b;
            return root.descending ? -order : order;
        });
        return rows;
    }

    // Off-screen builders: one per entry, alive for as long as the table is,
    // reporting once. `visible: false` rather than a zero size, because a
    // control asked to lay out at zero reports the size it was squeezed to.
    Item {
        visible: false
        Repeater {
            model: root.entries
            delegate: ComponentStage {
                id: prober
                required property var modelData
                entry: modelData
                onMeasurementsChanged: {
                    if (measurements)
                        root.record(prober.entry.type, measurements);
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- header, and the sort ----------------------------------------
        //
        // Laid out with the ROWS' geometry - same left inset, same cell
        // widths - rather than as a ButtonGroup of pills. The pills took the
        // group's fill width for themselves, so "Component" became a 660px
        // bar and every other heading sat a full column off the numbers it
        // named.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Appearance.spacing.space100 + Appearance.spacing.space150
            Layout.rightMargin: Appearance.spacing.space100 + Appearance.spacing.space150
            Layout.bottomMargin: Appearance.spacing.space50
            spacing: 0

            Repeater {
                model: root.columns
                delegate: Item {
                    id: header
                    required property var modelData
                    readonly property bool active: root.sortKey === header.modelData.key
                    Layout.preferredWidth: header.modelData.width
                    implicitHeight: 28

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (header.active)
                                root.descending = !root.descending;
                            else {
                                root.sortKey = header.modelData.key;
                                root.descending = false;
                            }
                        }
                    }
                    RowLayout {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        spacing: Appearance.spacing.space25
                        StyledText {
                            font.weight: Font.Medium
                            color: header.active
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSubtext
                            text: header.modelData.name
                        }
                        MaterialSymbol {
                            visible: header.active
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                            text: root.descending ? "arrow_downward" : "arrow_upward"
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: rowGroup.implicitHeight
            clip: true

            GroupedList {
                id: rowGroup
                anchors { left: parent.left; right: parent.right; top: parent.top }
                cohesive: true
                model: root.rows
                rowDelegate: Component {
                    DialogListItem {
                        id: row
                        property var modelData: null
                        implicitHeight: 32
                        onClicked: {
                            if (row.modelData?.entry)
                                root.picked(row.modelData.entry);
                        }

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: Appearance.spacing.space150
                                rightMargin: Appearance.spacing.space150
                            }
                            spacing: 0

                            StyledText {
                                Layout.preferredWidth: root.columns[0].width
                                elide: Text.ElideRight
                                // A widget that could not be built has no
                                // numbers, and a name in full strength beside
                                // a row of dashes reads as a measurement of
                                // zero rather than as "not measured".
                                color: row.modelData?.built
                                    ? Appearance.colors.colOnLayer2
                                    : Appearance.colors.colSubtext
                                text: row.modelData?.type ?? ""
                            }
                            Repeater {
                                model: root.columns.slice(1)
                                delegate: StyledText {
                                    id: cell
                                    required property var modelData
                                    Layout.preferredWidth: cell.modelData.width
                                    color: Appearance.colors.colOnLayer2
                                    text: {
                                        const value = row.modelData?.[cell.modelData.key];
                                        if (value === undefined)
                                            return "—";
                                        return typeof value === "number"
                                            ? value.toFixed(0) : `${value}`;
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }
}
