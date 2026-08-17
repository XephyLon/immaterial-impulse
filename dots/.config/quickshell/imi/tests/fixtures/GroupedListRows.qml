import QtQuick
import qs.modules.common.widgets

/**
 * Three rows in a real `GroupedList`, for tst_grouped_list.qml.
 *
 * A separate file rather than an inline `Component` because the widget uses
 * per-corner `Rectangle` radii, which Qt gained in 6.7 - and an inline
 * component is compiled with the test file, so on an older Qt the whole
 * TestCase fails to compile and every case in it is lost rather than one being
 * skipped. Loaded through `Qt.createComponent`, the version dependency is a
 * status the test can read and report.
 */
GroupedList {
    width: 300

    property alias firstRow: first
    property alias middleRow: middle
    property alias lastRow: last

    Item {
        id: first
        implicitHeight: 40
        property bool rowVisible: true
    }
    Item {
        id: middle
        implicitHeight: 40
        property bool rowVisible: true
    }
    // Declares nothing, which is what almost every row in the shell does - it
    // must still be drawn, and it must still be able to hold the group's
    // bottom corner.
    Item { id: last; implicitHeight: 40 }
}
