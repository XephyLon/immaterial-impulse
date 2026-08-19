import QtQuick
import "../../../../common/functions/quick_toggle_layout.js" as QuickToggleLayout

/**
 * The Android quick toggle grid's rows, keyed by a stable id.
 *
 * The panel used to hand each row of the grid a plain JS array, so every layout
 * edit reset that row's `Repeater` and rebuilt its delegates. That is what kept
 * `DelegateChooser` honest (81379796b ("fix(sidebar): choose a delegate for the
 * toggle each row entry now holds")) and it is also why a reorder could not
 * animate: the tile the user dragged is destroyed at the moment it should be
 * travelling.
 *
 * This keeps the delegates and gets the same guarantee from the other side. A
 * reorder is emitted as a real `move`, so the delegate is reused; a row's id is
 * derived from its toggle type, so the role the chooser reads never changes
 * under a surviving delegate; and `update` may write only the payload roles, so
 * there is no spelling here that could retype a live row even by accident.
 *
 * `sync` is the only writer, it is idempotent, and the arithmetic behind it is
 * in `quick_toggle_layout.js` - this file owns nothing but the model's
 * lifetime.
 */
ListModel {
    id: root

    // Rows, not tiles: the grid packs by size, so this is a function of the
    // toggle sizes and the column count rather than of the number of entries.
    property int gridRows: 0

    function sync(entries, columns) {
        const desired = QuickToggleLayout.pack(entries, columns);

        const current = [];
        for (let i = 0; i < root.count; i++) current.push(root.get(i));

        for (const op of QuickToggleLayout.syncPlan(current, desired)) {
            if (op.op === "remove") root.remove(op.index, 1);
            else if (op.op === "insert") root.insert(op.index, op.entry);
            else if (op.op === "move") root.move(op.from, op.to, 1);
            else if (op.op === "update") {
                for (const role of QuickToggleLayout.PAYLOAD_ROLES)
                    root.setProperty(op.index, role, op.entry[role]);
            }
        }

        root.gridRows = QuickToggleLayout.rowCount(desired);
    }
}
