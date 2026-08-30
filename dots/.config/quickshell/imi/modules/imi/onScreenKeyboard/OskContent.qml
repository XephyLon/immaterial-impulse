import qs.services
import qs.modules.common
import "layouts.js" as Layouts
import "key_shapes.js" as KeyShapes
import "osk_lattice.js" as Lattice
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property var layouts: Layouts.byName
    property var activeLayoutName: (layouts.hasOwnProperty(Config.options?.osk.layout))
        ? Config.options?.osk.layout
        : Layouts.defaultLayout
    property var currentLayout: layouts[activeLayoutName]

    // The gap OskKey subtracts from every span it draws. One value read by
    // both, or a key wider than one unit is drawn short by the difference.
    readonly property real keyGap: Appearance.spacing.space100
    readonly property var placements: Lattice.place(root.currentLayout.keys)

    implicitWidth: keyGrid.implicitWidth
    // The lattice row draws nothing and is one row tall, so the grid stands one
    // rowSpacing taller than the keyboard. Reported off rather than absorbed by
    // resizing the grid: a grid given less height than it asked for takes the
    // difference out of a row of keys.
    implicitHeight: keyGrid.implicitHeight - keyGrid.rowSpacing

    // Deliberately not anchors.fill - see implicitHeight above.
    GridLayout {
        id: keyGrid
        columns: Lattice.columnsIn(root.placements)
        columnSpacing: root.keyGap
        rowSpacing: root.keyGap

        // The lattice, declared. A GridLayout does not land on a uniform column
        // on its own: it spreads a multi-column item's width over the columns
        // it spans, and measured over these three layouts that comes out 1197px
        // wide against the 1188 the units buy, with a 13px gap before Backspace
        // where every other gap is 8. One zero-height item per column, asking
        // for exactly one column, is what pins it - and it is a row of its own
        // because the engine refuses a second item in a cell already taken.
        Repeater {
            model: keyGrid.columns

            delegate: Item {
                required property int index
                Layout.row: root.currentLayout.keys.length
                Layout.column: index
                Layout.preferredWidth: Lattice.columnWidth(KeyShapes.baseKeyWidth, root.keyGap)
                Layout.preferredHeight: 0
            }
        }

        Repeater {
            model: root.placements

            // A placement looks like this: {key: {...}, row: 3, column: 88, columnSpan: 4, rowSpan: 2}
            delegate: OskKey {
                id: oskKey
                required property var modelData
                keyData: modelData.key
                Layout.row: modelData.row
                Layout.column: modelData.column
                Layout.columnSpan: modelData.columnSpan
                Layout.rowSpan: modelData.rowSpan

                // The board owns the input service and the keyboard's state;
                // a key is handed what it needs to draw and asks for what it
                // wants done.
                isShift: Ydotool.shiftKeys.includes(oskKey.keycode)
                shiftMode: Ydotool.shiftMode
                physicallyDown: KeyMonitor.pressed[oskKey.keycode] === true
                locked: (oskKey.isCapsLock && KeyboardLocks.capsLockOn)
                    || (oskKey.isNumLock && KeyboardLocks.numLockOn)
                onPressKey: keycode => Ydotool.press(keycode)
                onReleaseKey: keycode => Ydotool.release(keycode)
                onShiftModeRequested: mode => Ydotool.shiftMode = mode
                onShiftKeysReleaseRequested: Ydotool.releaseShiftKeys()
            }
        }
    }
}
